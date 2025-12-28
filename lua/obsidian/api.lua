---builtin functions that are impure, interacts with editor state, like vim.api

local M = {}
local log = require "obsidian.log"
local util = require "obsidian.util"
local iter, string, table = vim.iter, string, table
local Path = require "obsidian.path"
local search = require "obsidian.search"
local config = require "obsidian.config"

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
---@return obsidian.Workspace
M.find_workspace = function(path)
  return vim.iter(Obsidian.workspaces):find(function(ws)
    return M.path_is_note(path, ws)
  end)
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

  for match in iter(search.find_tags_in_string(current_line)) do
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

---Check if a string is a checkbox list item
---
---Supported checboox lists:
--- - [ ] foo
--- - [x] foo
--- + [x] foo
--- * [ ] foo
--- 1. [ ] foo
--- 1) [ ] foo
---
---@param s string
---@return boolean
local is_checkbox = function(s)
  -- - [ ] and * [ ] and + [ ]
  if string.match(s, "%s*[-+*]%s+%[.%]") ~= nil then
    return true
  end
  -- 1. [ ] and 1) [ ]
  if string.match(s, "%s*%d+[%.%)]%s+%[.%]") ~= nil then
    return true
  end
  return false
end

M._is_checkbox = is_checkbox

--- Whether there is a checkbox under the cursor
---@return boolean
M.cursor_checkbox = function()
  return is_checkbox(vim.api.nvim_get_current_line())
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

  if not vim.endswith(prompt, " ") then
    prompt = prompt .. " "
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
---
---@param prompt string
---
---@return boolean
M._confirm = function(prompt)
  if not vim.endswith(util.rstrip_whitespace(prompt), "[Y/n]") then
    prompt = util.rstrip_whitespace(prompt) .. " [Y/n] "
  end

  local confirmation = M.input(prompt)
  if confirmation == nil then
    return false
  end

  confirmation = string.lower(confirmation)

  if confirmation == "" or confirmation == "y" or confirmation == "yes" then
    return true
  else
    return false
  end
end

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
  if util.is_url(path) then
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

--- Resolve a basename to full path inside the vault.
---
---@param src string
---@return string
M.resolve_image_path = function(src)
  local img_folder = Obsidian.opts.attachments.img_folder

  ---@cast img_folder -nil
  if vim.startswith(img_folder, ".") then
    local dirname = Path.new(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
    return tostring(dirname / img_folder / src)
  else
    return tostring(Obsidian.dir / img_folder / src)
  end
end

--- Follow a link. If the link argument is `nil` we attempt to follow a link under the cursor.
---
---@param link string
---@param opts { open_strategy: obsidian.config.OpenStrategy|? }|?
M.follow_link = function(link, opts)
  opts = opts and opts or {}
  require("obsidian.lsp.handlers._definition").follow_link(link, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    local cmd = opts.open_strategy or M.get_open_strategy(Obsidian.opts.open_notes_in)
    if #items == 1 then
      M.open_note(items[1], cmd)
    else
      Obsidian.picker.pick(items, { prompt_title = "Resolve link" }) -- calls open_qf_entry by default
    end
  end)
end

--------------------------
---- Mapping functions ---
--------------------------

---@param direction "next" | "prev"
M.nav_link = function(direction)
  -- vim.validate("direction", direction, "string", false, "nav_link must be called with a direction")
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local Note = require "obsidian.note"

  local matches = Note.from_buffer(0):links()

  if direction == "next" then
    for i = 1, #matches do
      local match = matches[i]
      if (match.line > cursor_line) or (cursor_line == match.line and cursor_col < match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  end

  if direction == "prev" then
    for i = #matches, 1, -1 do
      local match = matches[i]
      if (match.line < cursor_line) or (cursor_line == match.line and cursor_col > match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  end
end

local function has_markdown_folding()
  if vim.g.markdown_folding == 1 then
    return true
  elseif vim.wo.foldmethod == "expr" then
    return true
  end
  return false
end

-- If cursor is on a link, follow the link
-- If cursor is on a tag, show all notes with that tag in a picker
-- If cursor is on a checkbox, toggle the checkbox
-- If cursor is on a heading, cycle the fold of that heading
M.smart_action = function()
  local legacy = Obsidian.opts.legacy_commands
  if M.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  elseif M.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  elseif has_markdown_folding() and M.cursor_heading() then
    return "za"
  elseif M.cursor_checkbox() or Obsidian.opts.checkbox.create_new then
    return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
  else
    return "<CR>"
  end
end

---Check if we are in node that should not do checkbox operations.
---
---@return boolean
local function no_checkbox()
  return util.in_node {
    "fenced_code_block",
    "minus_metadata",
    --- what other types?
  }
end

---Toggle the checkbox on the current line.
---
---@param states table|nil Optional table containing checkbox states (e.g., {" ", "x"}).
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.toggle_checkbox = function(states, line_num)
  if no_checkbox() then
    return
  end
  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  local checkboxes = states or { " ", "x" }

  if is_checkbox(line) then
    for i, check_char in ipairs(checkboxes) do
      if string.match(line, "^.* %[" .. vim.pesc(check_char) .. "%].*") then
        i = i % #checkboxes
        line = string.gsub(line, vim.pesc("[" .. check_char .. "]"), "[" .. checkboxes[i + 1] .. "]", 1)
        break
      end
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(line, unordered_list_pattern) then
      line = string.gsub(line, unordered_list_pattern, "%1- [ ] %2")
    else
      line = string.gsub(line, "^(%s*)", "%1- [ ] ")
    end
  else
    return
  end

  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { line })
end

---Set the checkbox on the current line to a specific state.
---
---@param state string|nil Optional string of state to set the checkbox to (e.g., " ", "x").
M.set_checkbox = function(state)
  if no_checkbox() then
    return
  end
  if state == nil then
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      log.err "set_checkbox: unable to get state input"
      return
    end
    state = string.char(key + 0)
  end

  local found = false
  for _, value in ipairs(Obsidian.opts.checkbox.order) do
    if value == state then
      found = true
    end
  end

  if not found then
    log.err(
      "state passed '"
        .. state
        .. "' is not part of the available states: "
        .. vim.inspect(Obsidian.opts.checkbox.order)
    )
    return
  end

  local cur_line = vim.api.nvim_get_current_line()

  if is_checkbox(cur_line) then
    if string.match(cur_line, "^.* %[.%].*") then
      cur_line = string.gsub(cur_line, "%[.%]", "[" .. state .. "]", 1)
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(cur_line, unordered_list_pattern) then
      cur_line = string.gsub(cur_line, unordered_list_pattern, "%1- [" .. state .. "] %2")
    else
      cur_line = string.gsub(cur_line, "^(%s*)", "%1- [" .. state .. "] ")
    end
  else
    return
  end

  local line_num = vim.fn.getpos(".")[2]
  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { cur_line })
end

--- Calculate the byte position after a UTF-8 character at the given byte position.
--- This is needed because visual selection cecol points to the start byte of the last
--- selected character, but we need the position after the full character.
---
---@param line string The line content
---@param byte_pos integer The 1-indexed byte position of the character start
---@return integer The 1-indexed byte position after the character (exclusive end)
local function get_utf8_char_end(line, byte_pos)
  if not line or byte_pos > #line then
    return byte_pos
  end
  local byte = line:byte(byte_pos)
  if not byte then
    return byte_pos
  end
  -- Determine UTF-8 character byte length from lead byte
  local char_bytes = 1
  if byte >= 240 then -- 11110xxx: 4-byte char
    char_bytes = 4
  elseif byte >= 224 then -- 1110xxxx: 3-byte char
    char_bytes = 3
  elseif byte >= 192 then -- 110xxxxx: 2-byte char
    char_bytes = 2
  end
  return byte_pos + char_bytes
end

local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1

--- Create an LSP TextEdit from a visual selection.
--- The edit uses UTF-8 byte offsets (matching our LSP server's offset_encoding).
---
---@param viz obsidian.selection The visual selection
---@param new_text string The replacement text
---@param bufnr integer? Buffer number (defaults to current buffer)
---@return lsp.TextDocumentEdit
local function make_text_edit(viz, new_text, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_buf_get_lines(bufnr, viz.cerow - 1, viz.cerow, false)[1]

  -- Calculate the exclusive end position (byte after the last selected character)
  local end_col = get_utf8_char_end(line, viz.cecol)

  return {
    textDocument = {
      uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr)),
      version = has_nvim_0_12 and vim.NIL or nil,
    },
    edits = {
      {
        range = {
          -- LSP positions are 0-indexed
          start = { line = viz.csrow - 1, character = viz.cscol - 1 },
          ["end"] = { line = viz.cerow - 1, character = end_col - 1 },
        },
        newText = new_text,
      },
    },
  }
end

--- Replace the visual selection with new text.
--- Returns the text edit that was (or would be) applied.
---
---@param viz obsidian.selection
---@param new_text string
---@param opts { apply: boolean? }? Options. apply defaults to true.
---@return lsp.TextDocumentEdit
local function replace_selection(viz, new_text, opts)
  opts = opts or {}
  local apply = opts.apply ~= false -- default to true

  local text_edit = make_text_edit(viz, new_text)

  if apply then
    vim.lsp.util.apply_workspace_edit({ documentChanges = { text_edit } }, "utf-8")
    require("obsidian.ui").update(0)
  end

  return text_edit
end

M.link = function()
  local viz = M.get_visual_selection()
  if not viz then
    log.err "`Obsidian link` must be called in visual mode"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  local query = viz.selection

  Obsidian.picker.find_notes {
    prompt_title = "Select note to link",
    query = query,
    callback = function(path)
      local note = require("obsidian.note").from_file(path)
      replace_selection(viz, note:format_link { label = viz.selection })
    end,
  }
end

---@param label string?
M.link_new = function(label)
  local viz = M.get_visual_selection()
  if not viz then
    log.err "`Obsidian link_new` must be called in visual mode"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  if not label or string.len(label) <= 0 then
    label = viz.selection
  end

  local note = require("obsidian.note").create { id = label }
  replace_selection(viz, note:format_link { label = label })

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"
end

---Extract the selected text into a new note
---and replace the selection with a link to the new note.
---@param label string?
M.extract_note = function(label)
  local viz = M.get_visual_selection()
  if not viz then
    log.err "`Obsidian extract_note` must be called in visual mode"
    return
  end

  local content = vim.split(viz.selection, "\n", { plain = true })

  ---@type string|?
  if label ~= nil and string.len(label) > 0 then
    label = vim.trim(label)
  else
    label = M.input "Enter title (optional): "
    if not label then
      log.warn "Aborted"
      return
    elseif label == "" then
      label = nil
    end
  end

  -- create the new note.
  local note = require("obsidian.note").create { id = label }

  -- replace selection with link to new note
  local link = note:format_link()
  replace_selection(viz, link)

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"

  -- add the selected text to the end of the new note
  note:open { sync = true }
  vim.api.nvim_buf_set_lines(0, -1, -1, false, content)
end

---@param id string|?
---@param template string|?
---@param callback fun(note: obsidian.Note)|?
M.new_from_template = function(id, template, callback)
  local Note = require "obsidian.note"

  local templates_dir = M.templates_dir()
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end

  if id ~= nil and template ~= nil then
    local note = Note.create {
      id = id,
      template = template,
      should_write = true,
    }
    if callback then
      callback(note)
    else
      note:open { sync = true }
    end
    return
  end

  Obsidian.picker.find_files {
    prompt_title = "Templates",
    dir = templates_dir,
    no_default_mappings = true,
    callback = function(template_name)
      if id == nil or id == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(util.input, "Enter title or path (optional): ", { completion = "file" })
        id = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          return
        elseif safe_title == "" then
          id = nil
        end
      end

      if template_name == nil or template_name == "" then
        log.warn "Aborted"
        return
      end

      ---@type obsidian.Note
      local note = Note.create { id = id, template = template_name, should_write = true }

      if callback then
        callback(note)
      else
        note:open { sync = false } -- TODO:??
      end
    end,
  }
end

return M
