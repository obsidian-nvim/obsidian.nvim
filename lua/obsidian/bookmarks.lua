local log = require "obsidian.log"
local Note = require "obsidian.note"
local picker = require "obsidian.picker"
local api = require "obsidian.api"

local M = {}

---@class obsidian.Bookmark
---@field ctime integer
---@field type "group" | "file" | "folder" | "search" | "url"
---@field path string
---@field _path string resolved path
---@field subpath string
---@field title string
---@field query string
---@field items obsidian.Bookmark[]
---@field url string|?

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
    vim.cmd("edit " .. entry.filename)
  end
end

---@param bookmarks obsidian.Bookmark[]
M.pick = function(bookmarks)
  bookmarks = vim
    .iter(bookmarks)
    :map(function(bm)
      if bm.path then
        bm._path = tostring(Obsidian.dir / bm.path)
      end
      return bm
    end)
    :filter(function(bm)
      if bm.path then
        return vim.uv.fs_stat(bm._path) ~= nil
      end
      return true
    end)
    :totable()

  vim.ui.select(bookmarks, {
    prompt_title = "Bookmarks",
    format_item = format_bookmark,
    preview_item = preview_bookmark,
  }, open_bookmark)
end

return M
