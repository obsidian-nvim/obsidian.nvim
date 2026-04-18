local M = {}
local log = require "obsidian.log"
local Note = require "obsidian.note"
local picker = require "obsidian.picker"
local api = require "obsidian.api"

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

      if bookmark.title then
        return bookmark.title
      elseif bookmark.query then
        return "query: " .. bookmark.query
      elseif bookmark.path then
        return bookmark.path .. (bookmark.subpath and bookmark.subpath or "")
      end
      return entry.text or bookmark.title
    end,
    preview_item = function()
      -- url -> defuddle.md
      -- group -> list items in a buf
      -- search -> proper obsidian search term parser
      -- file -> default preview
    end,
  })
end

---@param src string
---@return obsidian.PickerEntry[]
M.parse = function(src)
  local obj = vim.json.decode(src)
  return vim.tbl_map(bookmark_to_picker_entry, obj.items)
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

return M
