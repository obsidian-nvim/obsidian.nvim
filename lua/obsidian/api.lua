---builtin functions that are impure, interacts with editor state, like vim.api

local M = {}
local log = require "obsidian.log"
local util = require "obsidian.util"
local iter, string, table = vim.iter, string, table
local Path = require "obsidian.path"
local search = require "obsidian.search"
local config = require "obsidian.config"
local attachment = require "obsidian.attachment"

M.dir = require("obsidian.fs").dir

--- TODO: will not work if plugin is managed by nix
---
---@return obsidian.Path|?
M.docs_dir = function()
  local info = M.get_plugin_info "obsidian.nvim"
  if not info then
    return
  end

  ---@type obsidian.Path
  local dir = Path.new(info.path) / "docs"
  return dir
end

--- Get the templates folder.
---
---@param workspace obsidian.Workspace?
---@return obsidian.Path|?
M.templates_dir = function(workspace)
  local opts = Obsidian.opts

  if workspace and workspace ~= Obsidian.workspace then
    opts = config.normalize(workspace.overrides, Obsidian._opts)
  end

  if opts.templates == nil or opts.templates.folder == nil then
    return nil
  end

  local paths_to_check = { Obsidian.workspace.root / opts.templates.folder, Path.new(opts.templates.folder) }
  for _, path in ipairs(paths_to_check) do
    if path:is_dir() then
      return path
    end
  end

  log.err_once("'%s' is not a valid templates directory", opts.templates.folder)
  return nil
end

--- Check if a path represents a note in the workspace.
---
---@param path string|obsidian.Path
---@param workspace obsidian.Workspace|?
---
---@return boolean
M.path_is_note = function(path, workspace)
  path = Path.new(path):resolve()
  workspace = workspace or Obsidian.workspace

  local in_vault = path.filename:find(vim.pesc(tostring(workspace.root))) ~= nil
  if not in_vault then
    return false
  end

  -- Check file extension instead of vim.filetype.match to avoid fast event
  -- context issues. vim.filetype.match calls getenv() which is not allowed in
  -- completion context.
  local extension = tostring(path):match "%.([^%.]+)$"
  if not vim.list_contains({ "md", "markdown", "qmd" }, extension) then
    return false
  end

  -- Ignore markdown files in the templates directory.
  local templates_dir = M.templates_dir(workspace)
  if templates_dir ~= nil then
    if templates_dir:is_parent_of(path) then
      return false
    end
  end

  return true
end

-- find workspaces of a path
---@param path string|obsidian.Path
---@return obsidian.Workspace|?
M.find_workspace = function(path)
  return vim.iter(Obsidian.workspaces):find(function(ws)
    return M.path_is_note(path, ws)
  end)
end

---@return obsidian.Path workspace_root
M.resolve_workspace_dir = function()
  local ws
  if vim.b.obsidian_buffer then
    ws = M.find_workspace(vim.api.nvim_buf_get_name(0))
  end
  if ws then
    return ws.root
  else
    return Obsidian.workspace.root
  end
end

--- Get the current note from a buffer.
---
---@param bufnr integer|?
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.Note|?
M.current_note = function(bufnr, opts)
  bufnr = bufnr or 0
  local Note = require "obsidian.note"
  if not M.find_workspace(vim.api.nvim_buf_get_name(bufnr)) then
    return nil
  end

  opts = opts or {}
  if not opts.max_lines then
    opts.max_lines = Obsidian.opts.search.max_lines
  end
  return Note.from_buffer(bufnr, opts)
end

---@return [number, number, number, number] tuple containing { buf, win, row, col }
M.get_active_window_cursor_location = function()
  local buf = vim.api.nvim_win_get_buf(0)
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local location = { buf, win, row, col }
  return location
end

---Return the full link under cursor
---
---@return string? link
---@return obsidian.search.RefTypes? link_type
M.cursor_link = function()
  local line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = cur_col + 1 -- 0-indexed column to 1-indexed lua string position

  local refs = search.find_refs(line, { exclude = { "Tag" } })

  local match = iter(refs):find(function(m)
    local open, close = unpack(m)
    return cur_col >= open and cur_col <= close
  end)
  if match then
    return line:sub(match[1], match[2]), match[3]
  end
end

---Get the tag under the cursor, if there is one.
---@return string?
M.cursor_tag = function()
  local current_line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for _, match in ipairs(util.parse_tags(current_line)) do
    local open, close, _ = unpack(match)
    if open <= cur_col and cur_col <= close then
      return string.sub(current_line, open + 1, close)
    end
  end

  return nil
end

--- Get the heading under the cursor, if there is one.
---@return { header: string, level: integer, anchor: string }|?
M.cursor_heading = function()
  return util.parse_header(vim.api.nvim_get_current_line())
end

--- Whether there is a checkbox under the cursor
---@return boolean
M.cursor_checkbox = function()
  return util.is_checkbox(vim.api.nvim_get_current_line())
end

------------------
--- buffer api ---
------------------

--- Check if a buffer is empty.
---
---@param bufnr integer|?
---
---@return boolean
M.buffer_is_empty = function(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_line_count(bufnr) > 1 then
    return false
  else
    local first_text = vim.api.nvim_buf_get_text(bufnr, 0, 0, 0, 0, {})
    if vim.tbl_isempty(first_text) or first_text[1] == "" then
      return true
    else
      return false
    end
  end
end

--- Open a buffer for the corresponding path.
---
---@param path string|obsidian.Path
---@param opts { line: integer|?, col: integer|?, cmd: string|? }|?
---@return integer bufnr
---@deprecated
M.open_buffer = function(path, opts)
  vim.deprecate("api.open_buffer", "api.open_note", "4.0.0", "obsidian.nvim")
  opts = opts or {}
  return M.open_note({
    filename = tostring(path),
    lnum = opts.line,
    col = opts.col,
  }, opts.cmd)
end

--- Open a quickfix entry in buffer, with open strategy
---@param entry obsidian.PickerEntry|vim.quickfix.entry|string
---@param cmd string?
---@return integer
M.open_note = function(entry, cmd)
  local path
  if type(entry) == "string" then
    path = entry
  else
    path = entry.filename
  end
  cmd = vim.trim(cmd and cmd or "e")

  ---@type integer|?
  local result_bufnr

  -- Check for buffer in windows and use 'drop' command if one is found.
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == tostring(path) then
      cmd = "drop"
      result_bufnr = bufnr
      break
    end
  end

  vim.cmd(string.format("%s %s", cmd, vim.fn.fnameescape(tostring(path))))
  if type(entry) == "table" and entry.lnum then
    vim.api.nvim_win_set_cursor(0, { tonumber(entry.lnum), entry.col and entry.col or 0 })
  end

  if not result_bufnr then
    result_bufnr = vim.api.nvim_get_current_buf()
  end

  return result_bufnr
end

----------------
--- text api ---
----------------

---@class obsidian.selection
---@field lines string[]
---@field selection string
---@field csrow integer
---@field cerow integer
---@field cecol integer
---@field cscol integer

--- Get the current visual selection of text and exit visual mode.
---
---@param opts { strict: boolean|? }|?
---
---@return obsidian.selection|?
M.get_visual_selection = function(opts)
  opts = opts or {}
  -- Adapted from fzf-lua:
  -- https://github.com/ibhagwan/fzf-lua/blob/6ee73fdf2a79bbd74ec56d980262e29993b46f2b/lua/fzf-lua/utils.lua#L434-L466
  -- this will exit visual mode
  -- use 'gv' to reselect the text
  local _, csrow, cscol, cerow, cecol
  local mode = vim.fn.mode()
  if opts.strict and not vim.endswith(string.lower(mode), "v") then
    return
  end

  if mode == "v" or mode == "V" or mode == "" then
    -- if we are in visual mode use the live position
    _, csrow, cscol, _ = unpack(vim.fn.getpos ".")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "v")
    if mode == "V" then
      -- visual line doesn't provide columns
      cscol, cecol = 0, 999
    end
    -- exit visual mode
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
  else
    -- otherwise, use the last known visual position
    _, csrow, cscol, _ = unpack(vim.fn.getpos "'<")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "'>")
  end

  -- Swap vars if needed
  if cerow < csrow then
    csrow, cerow = cerow, csrow
    cscol, cecol = cecol, cscol
  elseif cerow == csrow and cecol < cscol then
    cscol, cecol = cecol, cscol
  end

  local lines = vim.fn.getline(csrow, cerow)
  assert(type(lines) == "table", "lines is not a table")
  if vim.tbl_isempty(lines) then
    return
  end

  -- When the whole line is selected via visual line mode ("V"), cscol / cecol will be equal to "v:maxcol"
  -- for some odd reason. So change that to what they should be here. See ':h getpos' for more info.
  local maxcol = vim.api.nvim_get_vvar "maxcol"
  if cscol == maxcol then
    cscol = vim.fn.strlen(lines[1])
  end
  if cecol == maxcol then
    cecol = vim.fn.strlen(lines[#lines])
  end

  -- Use nvim_buf_get_text which properly handles UTF-8 byte positions
  -- getpos() returns byte-indexed positions (1-indexed)
  -- Visual selection is inclusive, so cecol points to the last selected byte
  -- But if that byte is the start of a multi-byte UTF-8 character, we need all its bytes
  local bufnr = vim.api.nvim_get_current_buf()

  local line = vim.api.nvim_buf_get_lines(bufnr, cerow - 1, cerow, false)[1]

  -- Calculate the end position for text extraction (needs to account for UTF-8)
  local end_col_for_extraction = cecol
  if line and cecol <= #line then
    local byte = line:byte(cecol)
    if byte then
      -- Determine UTF-8 character byte length
      local char_bytes = 1
      if byte >= 240 then -- 11110xxx: 4-byte char
        char_bytes = 4
      elseif byte >= 224 then -- 1110xxxx: 3-byte char
        char_bytes = 3
      elseif byte >= 192 then -- 110xxxxx: 2-byte char
        char_bytes = 2
        -- else: 0xxxxxxx (1-byte) or 10xxxxxx (continuation byte, shouldn't happen)
      end
      -- Move end position to point AFTER the last byte of this character (exclusive end)
      end_col_for_extraction = cecol + char_bytes
    end
  end

  local selection_lines = vim.api.nvim_buf_get_text(
    bufnr,
    csrow - 1, -- start row (convert to 0-indexed)
    cscol - 1, -- start col in bytes (convert to 0-indexed)
    cerow - 1, -- end row (convert to 0-indexed)
    end_col_for_extraction - 1, -- end col: exclusive, convert to 0-indexed
    {}
  )

  local selection = table.concat(selection_lines, "\n")

  return {
    lines = lines,
    selection = selection,
    csrow = csrow,
    cscol = cscol,
    cerow = cerow,
    cecol = cecol,
  }
end

------------------
--- UI helpers ---
------------------

---Get the strategy for opening notes
---
---@param opt obsidian.config.OpenStrategy
---@return string
M.get_open_strategy = function(opt)
  local OpenStrategy = require("obsidian.config").OpenStrategy

  -- either 'leaf', 'row' for vertically split windows, or 'col' for horizontally split windows
  local cur_layout = vim.fn.winlayout()[1]

  if vim.startswith(OpenStrategy.hsplit, opt) then
    if cur_layout ~= "col" then
      return "split "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit, opt) then
    if cur_layout ~= "row" then
      return "vsplit "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit_force, opt) then
    return "vsplit "
  elseif vim.startswith(OpenStrategy.hsplit_force, opt) then
    return "hsplit "
  elseif vim.startswith(OpenStrategy.current, opt) then
    return "e "
  else
    log.err("undefined open strategy '%s'", opt)
    return "e "
  end
end

----------------------------
--- Integration helpers ----
----------------------------

--- Get the path to where a plugin is installed.
---
---@param name string
---@return string|?
local get_src_root = function(name)
  return vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
    return vim.endswith(path, name)
  end)
end

--- Get info about a plugin.
---
---@param name string
---
---@return { commit: string|?, path: string }|?
M.get_plugin_info = function(name)
  local src_root = get_src_root(name)
  if not src_root then
    return
  end
  local out = { path = src_root }
  local obj = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = src_root }):wait(1000)
  if obj.code == 0 then
    out.commit = vim.trim(obj.stdout)
  else
    out.commit = "unknown"
  end
  return out
end

--- Get info about a external dependency.
---
---@param cmd string
---@return string|?
M.get_external_dependency_info = function(cmd)
  local obj = vim.system({ cmd, "--version" }, {}):wait(1000)
  if obj.code ~= 0 then
    return
  end
  local version = vim.version.parse(obj.stdout)
  if version then
    return ("%d.%d.%d"):format(version.major, version.minor, version.patch)
  end
end

------------------
--- UI helpers ---
------------------

local INPUT_CANCELLED = "~~~INPUT-CANCELLED~~~"

--- Prompt user for an input. Returns nil if canceled, otherwise a string (possibly empty).
---
---@param prompt string
---@param opts { completion: string|?, default: string|? }|?
---
---@return string|?
M.input = function(prompt, opts)
  opts = opts or {}

  if not vim.endswith(prompt, ": ") then
    prompt = prompt .. ": "
  end

  local input = vim.trim(
    vim.fn.input { prompt = prompt, completion = opts.completion, default = opts.default, cancelreturn = INPUT_CANCELLED }
  )

  if input ~= INPUT_CANCELLED then
    return input
  else
    return nil
  end
end

--- Prompt user for a confirmation.
M.confirm = function(prompt, choices)
  choices = choices or "&Yes\n&No"
  local choices_tbl = vim.split(choices, "\n")
  choices_tbl = vim.tbl_map(function(choice)
    return choice:gsub("&", "")
  end, choices_tbl)

  local choice_idx = vim.fn.confirm(prompt, choices)
  local user_choice = choices_tbl[choice_idx]
  if not user_choice then
    return nil
  end
  if user_choice == "Yes" then
    return true
  elseif user_choice == "No" then
    return false
  else
    return user_choice
  end
end

---@enum OSType
M.OSType = {
  Linux = "Linux",
  Wsl = "Wsl",
  Windows = "Windows",
  Darwin = "Darwin",
  FreeBSD = "FreeBSD",
}

M._current_os = nil

---Get the running operating system.
---Reference https://vi.stackexchange.com/a/2577/33116
---@return OSType
M.get_os = function()
  if M._current_os ~= nil then
    return M._current_os
  end

  local this_os
  if vim.fn.has "win32" == 1 then
    this_os = M.OSType.Windows
  else
    local sysname = vim.uv.os_uname().sysname
    local release = vim.uv.os_uname().release:lower()
    if sysname:lower() == "linux" and string.find(release, "microsoft") then
      this_os = M.OSType.Wsl
    else
      this_os = sysname
    end
  end

  assert(this_os, "failed to get your os")
  M._current_os = this_os
  return this_os
end

--- Get a nice icon for a file or URL, if possible.
---
---@param path string
---
---@return string|?, string|? (icon, hl_group) The icon and highlight group.
M.get_icon = function(path)
  if util.is_uri(path) then
    local icon = ""
    local _, hl_group = M.get_icon "blah.html"
    return icon, hl_group
  elseif Path.new(path):is_dir() then
    return "󰉋"
  else
    local ok, res = pcall(function()
      local icon, hl_group = require("nvim-web-devicons").get_icon(path, nil, { default = true })
      return { icon, hl_group }
    end)
    if ok and type(res) == "table" then
      local icon, hlgroup = unpack(res)
      return icon, hlgroup
    elseif vim.endswith(path, ".md") then
      return ""
    end
  end
  return nil
end

M.resolve_attachment_path = attachment.resolve_attachment_path
M.resolve_image_path = attachment.resolve_attachment_path
M.is_attachment_path = attachment.is_attachment_path

setmetatable(M, {
  __index = function(_, k)
    return require("obsidian.actions")[k]
  end,
})

return M
