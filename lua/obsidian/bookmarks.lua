local log = require "obsidian.log"
local api = require "obsidian.api"

local M = {}

---@class obsidian.Bookmark
---@field ctime integer
---@field type "group" | "file" | "folder" | "search" | "url"
---@field path string?
---@field _path string? resolved path
---@field subpath string?
---@field title string?
---@field query string?
---@field items obsidian.Bookmark[]?
---@field url string?

---@type integer
local last_ctime = 0

---@return integer
M.new_ctime = function()
  local seconds, microseconds = vim.uv.gettimeofday()
  if not seconds or not microseconds then
    last_ctime = last_ctime + 1
    return last_ctime
  end
  local ctime = math.floor(seconds * 1000 + microseconds / 1000)
  ---@cast ctime integer
  if ctime <= last_ctime then
    ctime = last_ctime + 1
    ---@cast ctime integer
  end
  last_ctime = ctime
  return ctime
end

---@param opts { create: boolean? }?
---@return string?
M.resolve_bookmark_file = function(opts)
  opts = opts or {}
  local bookmark_file = api.resolve_workspace_dir() / ".obsidian" / "bookmarks.json"

  if not bookmark_file:exists() then
    if opts.create then
      local parent = bookmark_file:parent()
      if parent and not parent:exists() then
        vim.fn.mkdir(tostring(parent), "p")
      end
      local f = io.open(tostring(bookmark_file), "w")
      if not f then
        log.err "failed to create bookmarks file"
        return
      end
      f:write '{"items":[]}'
      f:close()
    else
      log.info "bookmark file does not exist"
      return
    end
  end
  return tostring(bookmark_file)
end

---@param create boolean
---@return string?, { items: obsidian.Bookmark[] }?
local function read_bookmark_file(create)
  local fp = M.resolve_bookmark_file { create = create }
  if not fp then
    return nil, nil
  end

  local f = io.open(fp, "r")
  if not f then
    log.err "failed to open bookmarks file"
    return nil, nil
  end
  local src = f:read "*a"
  f:close()

  local ok, obj = pcall(vim.json.decode, src)
  if not ok or type(obj) ~= "table" then
    log.err "failed to parse bookmarks file"
    return nil, nil
  end
  if obj.items == nil then
    obj.items = {}
  elseif type(obj.items) ~= "table" then
    log.err "invalid items in bookmarks file"
    return nil, nil
  end
  return fp, obj
end

---@param fp string
---@param obj { items: obsidian.Bookmark[] }
---@return boolean ok
local function write_bookmark_file(fp, obj)
  local out = io.open(fp, "w")
  if not out then
    log.err "failed to write bookmarks file"
    return false
  end
  out:write(vim.json.encode(obj))
  out:close()
  return true
end

---Append a bookmark to the vault's bookmarks.json file.
---@param bookmark obsidian.Bookmark
---@return boolean ok
M.add = function(bookmark)
  local fp, obj = read_bookmark_file(true)
  if not fp or not obj then
    return false
  end

  table.insert(obj.items, bookmark)
  return write_bookmark_file(fp, obj)
end

---@param items obsidian.Bookmark[]
---@param ctime integer
---@return obsidian.Bookmark?
local function remove_bookmark(items, ctime)
  for i, bookmark in ipairs(items) do
    if bookmark.ctime == ctime then
      return table.remove(items, i)
    end
    if bookmark.items then
      local removed = remove_bookmark(bookmark.items, ctime)
      if removed then
        return removed
      end
    end
  end
end

---@param bookmark obsidian.Bookmark
---@return boolean ok
M.del = function(bookmark)
  local fp, obj = read_bookmark_file(false)
  if not fp or not obj or not remove_bookmark(obj.items, bookmark.ctime) then
    return false
  end
  return write_bookmark_file(fp, obj)
end

---@return obsidian.Bookmark[]?
M.list = function()
  local _, obj = read_bookmark_file(false)
  return obj and obj.items or nil
end

---@param bookmark obsidian.Bookmark
---@param group obsidian.Bookmark|?
---@return boolean|? ok
M.move_to_group = function(bookmark, group)
  if not group then
    return require("obsidian.interfaces.bookmarks").move_to_group(bookmark)
  end

  local fp, obj = read_bookmark_file(false)
  if not fp or not obj then
    return false
  end

  local moved = remove_bookmark(obj.items, bookmark.ctime)
  if not moved then
    log.warn "Bookmark no longer exists"
    return false
  end

  local destination
  if group.ctime == -1 then
    destination = {
      ctime = M.new_ctime(),
      type = "group",
      title = group.title,
      items = {},
    }
    obj.items[#obj.items + 1] = destination
  else
    local function find_group(items)
      for _, item in ipairs(items) do
        if item.type == "group" then
          if item.ctime == group.ctime then
            return item
          end
          local found = find_group(item.items or {})
          if found then
            return found
          end
        end
      end
    end
    destination = find_group(obj.items)
    if not destination then
      log.warn "Bookmark group no longer exists"
      return false
    end
  end

  destination.items = destination.items or {}
  destination.items[#destination.items + 1] = moved
  return write_bookmark_file(fp, obj)
end

---@param src string
---@return obsidian.Bookmark[]
M.parse = function(src)
  local obj = vim.json.decode(src)
  return obj.items
end

---Backwards-compatible picker entry point.
---@param bookmarks obsidian.Bookmark[]|?
M.pick = function(bookmarks)
  return require("obsidian.interfaces.bookmarks").open(bookmarks)
end

return M
