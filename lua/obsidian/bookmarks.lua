local log = require "obsidian.log"
local Note = require "obsidian.note"
local picker = require "obsidian.picker"
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

---@param bookmark obsidian.Bookmark
---@return obsidian.PickerEntry entry
local function bookmark_to_picker_entry(bookmark)
  local entry = { text = bookmark.title, user_data = bookmark }

  if bookmark.path then
    entry.filename = bookmark._path
  end

  if bookmark.subpath then
    local ok, note = pcall(Note.from_file, entry.filename)
    if ok and note then
      ---@cast note -string
      ---@type obsidian.Section|?
      local section
      if vim.startswith(bookmark.subpath, "#^") then
        local block = note:resolve_block(bookmark.subpath:sub(2))
        section = block and block.section
        entry.lnum = section and section.range.start_row + 1 or (block and block.line or nil)
      elseif vim.startswith(bookmark.subpath, "#") then
        local anchor = note:resolve_anchor_link(bookmark.subpath)
        section = anchor and anchor.section
        entry.lnum = section and section.range.start_row + 1 or (anchor and anchor.line or nil)
      end

      if section then
        entry.range = section.range
      end
    else
      log.err("Failed to resolve bookmark path to note: %s", note)
    end
  end

  return entry
end

---@type table<string, string[]>
local url_cache = {}

local function format_bookmark(bookmark)
  if bookmark.type == "folder" then
    return bookmark.path .. "/"
  elseif bookmark.type == "group" then
    return "> " .. bookmark.title
  elseif bookmark.title then
    return bookmark.title
  elseif bookmark.query then
    return "query: " .. bookmark.query
  elseif bookmark.path then
    return bookmark.path .. (bookmark.subpath and bookmark.subpath or "")
  end
  return bookmark.title
end

---@alias obsidian.ui.select_preview_spec {buf?:integer, pos?:[integer,integer], pos_end?:[integer,integer]}

---@param bookmark obsidian.Bookmark
---@param buf integer
---@return obsidian.ui.select_preview_spec
local function preview_url(bookmark, buf)
  local url = bookmark.url
  if not url then
    return { buf = buf }
  end
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Fetching preview for url..." })
  if url_cache[url] then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, url_cache[url])
  else
    vim.system(
      { "curl", "https://defuddle.md/" .. url },
      {},
      vim.schedule_wrap(function(out)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if out.code ~= 0 or not out.stdout or out.stdout == "" then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Failed to fetch preview for " .. url })
          return
        end
        local lines = vim.split(out.stdout, "\n")
        url_cache[url] = lines
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      end)
    )
  end
  return { buf = buf }
end

---@param bookmark obsidian.Bookmark
---@param buf integer
---@return obsidian.ui.select_preview_spec
local function preview_group(bookmark, buf)
  vim.bo[buf].filetype = "markdown"
  local lines = vim.tbl_map(function(bm)
    return "- " .. format_bookmark(bm)
  end, bookmark.items)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return { buf = buf }
end

--  TODO: proper obsidian search term parser, like the explain search term feature
--
---@param bookmark obsidian.Bookmark
---@param buf integer
---@return obsidian.ui.select_preview_spec
local function preview_query(bookmark, buf)
  vim.bo[buf].filetype = "markdown"
  local lines = { "query: " .. bookmark.query }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return { buf = buf }
end

---@param bookmark obsidian.Bookmark
---@param buf integer
---@return obsidian.ui.select_preview_spec
local function preview_file(bookmark, buf)
  if not bookmark.path then
    return { buf = buf }
  end
  local entry = bookmark_to_picker_entry(bookmark)
  if not entry.filename then
    return { buf = buf }
  end
  local lines = vim.fn.readfile(entry.filename)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return { buf = buf, pos = entry.lnum and { entry.lnum, 0 } or nil }
end

---@param bookmark obsidian.Bookmark
---@return obsidian.ui.select_preview_spec
local function preview_bookmark(bookmark)
  local buf = vim.api.nvim_create_buf(false, true)
  if bookmark.type == "url" then
    return preview_url(bookmark, buf)
  elseif bookmark.type == "group" then
    return preview_group(bookmark, buf)
  elseif bookmark.type == "search" then
    return preview_query(bookmark, buf)
  elseif bookmark.type == "file" then
    return preview_file(bookmark, buf)
  else
    return { buf = buf }
  end
end

---@param opts { create: boolean? }?
---@return string?
M.resolve_bookmark_file = function(opts)
  opts = opts or {}
  local bookmark_file = Obsidian.workspace.root / ".obsidian" / "bookmarks.json"

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
      log.info "bookmark file does not exist, adding and managing bookmarks is not supported yet"
      return
    end
  end
  return tostring(bookmark_file)
end

---Append a bookmark to the vault's bookmarks.json file.
---@param bookmark obsidian.Bookmark
---@return boolean ok
M.add = function(bookmark)
  local fp = M.resolve_bookmark_file { create = true }
  if not fp then
    return false
  end

  local f = io.open(fp, "r")
  if not f then
    log.err "failed to open bookmarks file"
    return false
  end
  local src = f:read "*a"
  f:close()

  local ok, obj = pcall(vim.json.decode, src)
  if not ok or type(obj) ~= "table" then
    obj = { items = {} }
  end
  obj.items = obj.items or {}
  table.insert(obj.items, bookmark)

  local out = io.open(fp, "w")
  if not out then
    log.err "failed to write bookmarks file"
    return false
  end
  out:write(vim.json.encode(obj))
  out:close()
  return true
end

---@param src string
---@return obsidian.Bookmark[]
M.parse = function(src)
  local obj = vim.json.decode(src)
  return obj.items
end

---@param bookmark obsidian.Bookmark?
local function open_bookmark(bookmark)
  if not bookmark then
    return
  end
  if bookmark.type == "url" and bookmark.url then
    vim.ui.open(bookmark.url)
  elseif bookmark.type == "group" then
    M.pick(bookmark.items)
  elseif bookmark.type == "search" and bookmark.query then
    -- TODO: proper obsidian search term parser and search
    picker.grep {
      query = bookmark.query,
    }
  elseif bookmark.type == "file" then
    api.open_note(bookmark_to_picker_entry(bookmark))
  elseif bookmark.type == "folder" then
    local entry = bookmark_to_picker_entry(bookmark)
    if entry.filename then
      vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
    end
  end
end

---@param bookmarks obsidian.Bookmark[]
M.pick = function(bookmarks)
  local filtered = {}
  for _, bm in ipairs(bookmarks) do
    if bm.path then
      bm._path = tostring(Obsidian.dir / bm.path)
    end
    if not bm.path or vim.uv.fs_stat(bm._path) ~= nil then
      filtered[#filtered + 1] = bm
    end
  end
  bookmarks = filtered

  vim.ui.select(bookmarks, {
    prompt_title = "Bookmarks",
    format_item = format_bookmark,
    preview_item = preview_bookmark,
  }, open_bookmark)
end

return M
