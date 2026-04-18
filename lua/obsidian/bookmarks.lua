local log = require "obsidian.log"
local Note = require "obsidian.note"
local picker = require "obsidian.picker"
local api = require "obsidian.api"

local M = {}

---@class obsidian.Bookmark
---@field ctime integer
---@field type "group" | "file" | "folder" | "search" | "url"
---@field path string
---@field subpath string
---@field title string
---@field query string
---@field items obsidian.Bookmark[]
---@field url string|?

---@param bookmark obsidian.Bookmark
---@return obsidian.PickerEntry entry
local function bookmark_to_picker_entry(bookmark)
  local entry = { text = bookmark.title }

  if bookmark.path then
    entry.filename = tostring(Obsidian.dir / bookmark.path)
  end

  if bookmark.subpath then
    local ok, note = pcall(Note.from_file, entry.filename)
    if ok and note then
      ---@cast note -string
      if vim.startswith(bookmark.subpath, "#^") then
        local block = note:resolve_block(bookmark.subpath:sub(2))
        entry.lnum = block and block.line or nil
      elseif vim.startswith(bookmark.subpath, "#") then
        local anchor = note:resolve_anchor_link(bookmark.subpath)
        entry.lnum = anchor and anchor.line or nil
      end
    else
      log.err("Failed to resolve bookmark path to note: %s", note)
    end
  end

  entry.user_data = bookmark
  return entry
end

---@type table<string, string[]>
local url_cache = {}

local function format_bookmark(bookmark)
  if bookmark.type == "folder" then
    return bookmark.path .. "/"
  end

  if bookmark.title then
    return bookmark.title
  elseif bookmark.query then
    return "query: " .. bookmark.query
  elseif bookmark.path then
    return bookmark.path .. (bookmark.subpath and bookmark.subpath or "")
  end
  return bookmark.title
end

---@param bookmark obsidian.Bookmark
local function preview_url(bookmark)
  local url = bookmark.url
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Fetching preview for url..." })
  if url_cache[url] then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, url_cache[url])
  else
    vim.system(
      { "curl", "https://defuddle.md/" .. url },
      {},
      vim.schedule_wrap(function(out)
        local lines = vim.split(out.stdout, "\n")
        url_cache[url] = lines
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      end)
    )
  end
  return { buf = buf }
end

---@param bookmark obsidian.Bookmark
local function preview_group(bookmark)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  local lines = vim.tbl_map(function(bm)
    return "- " .. format_bookmark(bm)
  end, bookmark.items)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return { buf = buf }
end

--  TODO: proper obsidian search term parser, like the expalin search term feature
--
---@param bookmark obsidian.Bookmark
local function preview_query(bookmark)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  local lines = { "query: " .. bookmark.query }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return { buf = buf }
end

---@return string?
M.resolve_bookmark_file = function()
  local bookmark_file = Obsidian.workspace.root / ".obsidian" / "bookmarks.json"

  if not bookmark_file:exists() then
    log.info "bookmark file does not exist, adding and managing bookmarks is not supported yet"
    return
  end
  return tostring(bookmark_file)
end

---@param src string
---@return obsidian.PickerEntry[]
M.parse = function(src)
  local obj = vim.json.decode(src)
  return vim.tbl_map(bookmark_to_picker_entry, obj.items)
end

---@param entries obsidian.PickerEntry[]
M.pick = function(entries)
  picker.pick(entries, {
    prompt_title = "Bookmarks",
    callback = function(entry)
      ---@type obsidian.Bookmark
      local bookmark = entry.user_data
      if bookmark.type == "url" and bookmark.url then
        vim.ui.open(bookmark.url)
      elseif bookmark.type == "group" then
        local _entries = vim.tbl_map(bookmark_to_picker_entry, bookmark.items)
        M.pick(_entries)
      elseif bookmark.type == "search" and bookmark.query then
        -- proper obsidian search term parser
        picker.grep {
          query = bookmark.query,
        }
      elseif bookmark.type == "file" then
        api.open_note(entry)
      end
    end,
    format_item = function(entry)
      local bookmark = entry.user_data
      return format_bookmark(bookmark)
    end,
    preview_item = function(entry)
      local bookmark = entry.user_data
      ---@cast bookmark obsidian.Bookmark
      if bookmark.type == "url" then
        return preview_url(bookmark)
      elseif bookmark.type == "group" then
        return preview_group(bookmark)
      elseif bookmark.type == "search" then
        return preview_query(bookmark)
      end
    end,
  })
end

return M
