local M = {}
local log = require "obsidian.log"
local Note = require "obsidian.note"

---@class obsidian.bookmark
---@field ctime integer
---@field type "group" | "file" | "folder" | "search" TODO:
---@field path string
---@field subpath string
---@field title string
---@field query string

---@param bookmark obsidian.bookmark
---@return obsidian.PickerEntry entry
local function bookmark_to_picker_entry(bookmark)
  -- TODO: all pickers should run user_data if is function

  local entry = { text = bookmark.title }

  if bookmark.title then
    entry.text = bookmark.title
  elseif bookmark.query then
    entry.text = bookmark.query
  elseif bookmark.path then
    entry.text = bookmark.path .. (bookmark.subpath and bookmark.subpath or "")
  end

  if bookmark.query then
    local preview_tmp_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(preview_tmp_buf, 0, 1, true, { bookmark.query })

    entry.user_data = function()
      Obsidian.picker.find_notes {
        prompt_title = "Quick Switch",
        query = bookmark.query,
      }
    end
    entry.bufnr = preview_tmp_buf
  end

  if bookmark.path then
    entry.filename = tostring(Obsidian.dir / bookmark.path)
  end

  if bookmark.subpath then
    local note = Note.from_file(entry.filename)
    if vim.startswith(bookmark.subpath, "#^") then
      local block = note:resolve_block(bookmark.subpath:sub(2))
      entry.lnum = block and block.line or nil
    elseif vim.startswith(bookmark.subpath, "#") then
      local anchor = note:resolve_anchor_link(bookmark.subpath)
      entry.lnum = anchor and anchor.line or nil
    end
  end

  return entry
end

--- TODO: if false, list group just as an entry
vim.g.obsidian_bookmark_group = false

---@param path string
---@return obsidian.PickerEntry[]
M.parse = function(path)
  local f = io.open(path, "r")
  assert(f, "failed to open workspace file")
  local src = f:read "*a"
  f:close()
  local ok, obj = pcall(vim.json.decode, src)

  if not ok then
    ---@diagnostic disable-next-line: return-type-mismatch
    return log.error(obj)
  end

  local bookmarks = obj.items

  local entries = {}

  if not vim.g.obsidian_bookmark_group then
    for _, bookmark in ipairs(bookmarks) do
      if bookmark.type == "group" then
        for _, bm in ipairs(bookmark.items) do
          entries[#entries + 1] = bookmark_to_picker_entry(bm)
        end
      else
        entries[#entries + 1] = bookmark_to_picker_entry(bookmark)
      end
    end
  end

  return entries
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
