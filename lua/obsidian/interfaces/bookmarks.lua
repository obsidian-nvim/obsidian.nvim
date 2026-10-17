local picker = require "obsidian.picker"
local Note = require "obsidian.note"
local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.interfaces.util"
local shared_preview = require "obsidian.preview"
local picker_util = require "obsidian.picker.util"

local M = {}

---Resolve a bookmark's vault-relative path against the current workspace,
---caching the result on `bookmark._path`. Bookmarks without a `path`, or whose
---`path` is the empty string (e.g. the vault root), resolve to nil.
---
---@param bookmark obsidian.Bookmark
---@return string?
local function resolve_bookmark(bookmark, workspace_dir)
  if bookmark._path ~= nil then
    return bookmark._path
  end
  if not bookmark.path or bookmark.path == "" then
    return nil
  end
  workspace_dir = workspace_dir or api.resolve_workspace_dir()
  if workspace_dir then
    bookmark._path = vim.fs.joinpath(tostring(workspace_dir), bookmark.path)
  end
  return bookmark._path
end

---@param bookmark obsidian.Bookmark
---@return obsidian.PickerEntry entry
local function bookmark_to_picker_entry(bookmark, workspace_dir)
  local entry = { text = bookmark.title, user_data = bookmark }

  local path = resolve_bookmark(bookmark, workspace_dir)
  if path then
    entry.filename = path
  end

  if bookmark.subpath and path and vim.uv.fs_stat(path) ~= nil then
    local ok, note = pcall(Note.from_file, path)
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

-- TODO: one dir type helper

---@param bookmark obsidian.Bookmark
---@return obsidian.ui_select_preview_spec
local function preview_group(bookmark)
  local lines = vim.tbl_map(function(bm)
    return "- " .. format_bookmark(bm)
  end, bookmark.items or {})
  return shared_preview.text(lines, "markdown")
end

---@param bookmark obsidian.Bookmark
---@param context { bufnr: integer, winid: integer, workspace_dir: string? }
---@return obsidian.ui_select_preview_spec
local function preview_url(bookmark, context)
  local source_path = vim.api.nvim_buf_get_name(context.bufnr)
  return shared_preview.url {
    url = bookmark.url or "",
    bufnr = context.bufnr,
    source_path = source_path ~= "" and source_path or nil,
    workspace_dir = context.workspace_dir,
  }
end

--  TODO: proper obsidian search term parser, like the explain search term feature
--
---@param bookmark obsidian.Bookmark
---@return obsidian.ui_select_preview_spec
local function preview_query(bookmark)
  return shared_preview.text({ "query: " .. bookmark.query }, "markdown")
end

---@param bookmark obsidian.Bookmark
---@return obsidian.ui_select_preview_spec
local function preview_file(bookmark, workspace_dir)
  local path = resolve_bookmark(bookmark, workspace_dir)
  if not path or vim.uv.fs_stat(path) == nil then
    local label = bookmark.path and bookmark.path ~= "" and bookmark.path or "(unresolved path)"
    return shared_preview.text { "Bookmark target is missing: " .. label }
  end
  local entry = bookmark_to_picker_entry(bookmark, workspace_dir)
  return picker_util.preview_entry(entry)
end

---@param bookmark obsidian.Bookmark
---@return obsidian.ui_select_preview_spec
local function preview_bookmark(bookmark, context)
  if bookmark.type == "file" or bookmark.type == "folder" then
    return preview_file(bookmark, context.workspace_dir)
  end

  if bookmark.type == "url" then
    return preview_url(bookmark, context)
  elseif bookmark.type == "group" then
    return preview_group(bookmark)
  elseif bookmark.type == "search" then
    return preview_query(bookmark)
  else
    return shared_preview.text { "No preview available" }
  end
end

---@param bookmark obsidian.Bookmark?
local function open_bookmark(bookmark, context)
  if not bookmark or not util.context_is_valid(context) then
    return
  end
  if bookmark.type == "url" and bookmark.url then
    vim.ui.open(bookmark.url)
  elseif bookmark.type == "group" then
    M.open(bookmark.items or {}, { workspace_dir = context.workspace_dir })
  elseif bookmark.type == "search" and bookmark.query then
    -- TODO: proper Obsidian search term parser and search
    vim.api.nvim_win_call(context.winid, function()
      picker.grep_notes {
        query = bookmark.query,
        dir = context.workspace_dir,
      }
    end)
  elseif bookmark.type == "file" then
    local entry = bookmark_to_picker_entry(bookmark, context.workspace_dir)
    if entry.filename and vim.uv.fs_stat(entry.filename) ~= nil then
      vim.api.nvim_win_call(context.winid, function()
        api.open_note(entry)
      end)
    else
      log.warn("Bookmark target is missing: %s", bookmark.path or bookmark.title)
    end
  elseif bookmark.type == "folder" then
    local entry = bookmark_to_picker_entry(bookmark, context.workspace_dir)
    if entry.filename and vim.uv.fs_stat(entry.filename) ~= nil then
      vim.api.nvim_win_call(context.winid, function()
        vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
      end)
    else
      log.warn("Bookmark target is missing: %s", bookmark.path or bookmark.title)
    end
  end
end

-- TODO: allow overriding? picker opts? but what about resolvers for other ui?

---@param bookmark obsidian.Bookmark
M.move_to_group = function(bookmark)
  local Bookmarks = require "obsidian.bookmarks"
  local groups = {}
  local function collect(items)
    for _, item in ipairs(items) do
      if item.type == "group" then
        groups[#groups + 1] = item
        collect(item.items or {})
      end
    end
  end

  collect(Bookmarks.list() or {})
  groups[#groups + 1] = { ctime = -1, type = "group", title = "", items = {} }
  picker.select(groups, {
    prompt = "Move bookmark to group",
    format_item = function(group)
      return group.ctime == -1 and "+ Create new group" or (group.title or "Untitled group")
    end,
  }, function(choices)
    local group = choices and choices[1]
    if not group then
      return
    end
    if group.ctime == -1 then
      local title = api.input "New bookmark group name"
      if not title or title == "" then
        return
      end
      group.title = title
    end
    Bookmarks.move_to_group(bookmark, group)
  end)
end

---@param opts { bookmarks: obsidian.Bookmark[]?, workspace_dir: string?, bufnr: integer?, winid: integer?, picker: obsidian.PickerSelectOpts? }|?
---@param on_choice fun(bookmarks: obsidian.Bookmark[])|?
M.pick = function(opts, on_choice)
  opts = opts or {}
  local context = util.capture_context(opts)
  local Bookmarks = require "obsidian.bookmarks"
  local bookmarks = opts.bookmarks or Bookmarks.list() or {}
  if #bookmarks == 0 then
    return log.info "No bookmarks"
  end

  local mappings = {
    ["<C-q>"] = picker_util.send_to_qf_mapping {
      title = "Bookmarks",
      eligible = function(bookmark)
        return bookmark.type == "file"
      end,
      to_entry = function(bookmark)
        return bookmark_to_picker_entry(bookmark, context.workspace_dir)
      end,
    },
    ["<C-g>"] = { desc = "move to group", callback = M.move_to_group },
    ["<C-r>"] = {
      desc = "remove",
      callback = function(bookmark)
        if bookmark then
          Bookmarks.del(bookmark)
        end
      end,
    },
  }
  util.select(
    bookmarks,
    {
      prompt = "Bookmarks",
      allow_multiple = false,
      format_item = format_bookmark,
      preview_item = function(bookmark)
        return preview_bookmark(bookmark, context)
      end,
      selection_mappings = mappings,
    },
    opts.picker,
    function(choices)
      if on_choice then
        on_choice(choices)
      end
    end
  )
end

---@param bookmarks obsidian.Bookmark[]|?
---@param opts { workspace_dir: string?, bufnr: integer?, winid: integer?, picker: obsidian.PickerSelectOpts? }|?
M.open = function(bookmarks, opts)
  opts = opts or {}
  local context = util.capture_context(opts)
  local pick_opts = vim.tbl_extend("force", {}, opts, { bookmarks = bookmarks or opts.bookmarks })
  return M.pick(pick_opts, function(choices)
    open_bookmark(choices[1], context)
  end)
end

return M
