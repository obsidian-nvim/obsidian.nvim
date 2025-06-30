local M = {}
local log = require "obsidian.log"
local util = require "obsidian.util"
local ts, iter, string, table = vim.treesitter, vim.iter, string, table

---builtin functions that are impure, interacts with editor state, like vim.api

---Toggle the checkbox on the current line.
---
---@param states table|nil Optional table containing checkbox states (e.g., {" ", "x"}).
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.toggle_checkbox = function(states, line_num)
  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  local checkboxes = states or { " ", "x" }

  if util.is_checkbox(line) then
    for i, check_char in ipairs(checkboxes) do
      if string.match(line, "^.* %[" .. vim.pesc(check_char) .. "%].*") then
        i = i % #checkboxes
        line = string.gsub(line, vim.pesc("[" .. check_char .. "]"), "[" .. checkboxes[i + 1] .. "]", 1)
        break
      end
    end
  else
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(line, unordered_list_pattern) then
      line = string.gsub(line, unordered_list_pattern, "%1- [ ] %2")
    else
      line = string.gsub(line, "^(%s*)", "%1- [ ] ")
    end
  end

  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { line })
end

---@return [number, number, number, number] tuple containing { buf, win, row, col }
M.get_active_window_cursor_location = function()
  local buf = vim.api.nvim_win_get_buf(0)
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local location = { buf, win, row, col }
  return location
end

---Determines if cursor is currently inside markdown link.
---
---@param line string|nil - line to check or current line if nil
---@param col  integer|nil - column to check or current column if nil (1-indexed)
---@param include_naked_urls boolean|?
---@param include_file_urls boolean|?
---@param include_block_ids boolean|?
---@return integer|nil, integer|nil, obsidian.search.RefTypes|? - start and end column of link (1-indexed)
M.cursor_on_markdown_link = function(line, col, include_naked_urls, include_file_urls, include_block_ids)
  local search = require "obsidian.search"
  local current_line = line or vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = col or cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for match in
    iter(search.find_refs(current_line, {
      include_naked_urls = include_naked_urls,
      include_file_urls = include_file_urls,
      include_block_ids = include_block_ids,
    }))
  do
    local open, close, m_type = unpack(match)
    if open <= cur_col and cur_col <= close then
      return open, close, m_type
    end
  end

  return nil
end

--- Get the link location and name of the link under the cursor, if there is one.
---
---@param opts { line: string|?, col: integer|?, include_naked_urls: boolean|?, include_file_urls: boolean|?, include_block_ids: boolean|? }|?
---
---@return string|?, string|?, obsidian.search.RefTypes|?
M.parse_cursor_link = function(opts)
  opts = opts or {}

  local current_line = opts.line and opts.line or vim.api.nvim_get_current_line()
  local open, close, link_type = M.cursor_on_markdown_link(
    current_line,
    opts.col,
    opts.include_naked_urls,
    opts.include_file_urls,
    opts.include_block_ids
  )
  if open == nil or close == nil then
    return
  end

  local link = current_line:sub(open, close)
  return util.parse_link(link, {
    link_type = link_type,
    include_naked_urls = opts.include_naked_urls,
    include_file_urls = opts.include_file_urls,
    include_block_ids = opts.include_block_ids,
  })
end

---Get the tag under the cursor, if there is one.
---@return string?
M.cursor_tag = function()
  local search = require "obsidian.search"
  local current_line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for match in iter(search.find_tags(current_line)) do
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
M.open_buffer = function(path, opts)
  local Path = require "obsidian.path"
  path = Path.new(path):resolve()
  opts = opts and opts or {}
  local cmd = vim.trim(opts.cmd and opts.cmd or "e")

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
  if opts.line then
    vim.api.nvim_win_set_cursor(0, { tonumber(opts.line), opts.col and opts.col or 0 })
  end

  if not result_bufnr then
    result_bufnr = vim.api.nvim_get_current_buf()
  end

  return result_bufnr
end

---Get an iterator of (bufnr, bufname) over all named buffers. The buffer names will be absolute paths.
---
---@return function () -> (integer, string)|?
M.get_named_buffers = function()
  local idx = 0
  local buffers = vim.api.nvim_list_bufs()

  ---@return integer|?
  ---@return string|?
  return function()
    while idx < #buffers do
      idx = idx + 1
      local bufnr = buffers[idx]
      if vim.api.nvim_buf_is_loaded(bufnr) then
        return bufnr, vim.api.nvim_buf_get_name(bufnr)
      end
    end
  end
end

----------------
--- text api ---
----------------

--- Get the current visual selection of text and exit visual mode.
---
---@param opts { strict: boolean|? }|?
---
---@return { lines: string[], selection: string, csrow: integer, cscol: integer, cerow: integer, cecol: integer }|?
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
  assert(type(lines) == "table")
  if vim.tbl_isempty(lines) then
    return
  end

  -- When the whole line is selected via visual line mode ("V"), cscol / cecol will be equal to "v:maxcol"
  -- for some odd reason. So change that to what they should be here. See ':h getpos' for more info.
  local maxcol = vim.api.nvim_get_vvar "maxcol"
  if cscol == maxcol then
    cscol = string.len(lines[1])
  end
  if cecol == maxcol then
    cecol = string.len(lines[#lines])
  end

  ---@type string
  local selection
  local n = #lines
  if n <= 0 then
    selection = ""
  elseif n == 1 then
    selection = string.sub(lines[1], cscol, cecol)
  elseif n == 2 then
    selection = string.sub(lines[1], cscol) .. "\n" .. string.sub(lines[n], 1, cecol)
  else
    selection = string.sub(lines[1], cscol)
      .. "\n"
      .. table.concat(lines, "\n", 2, n - 1)
      .. "\n"
      .. string.sub(lines[n], 1, cecol)
  end

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
  if obj.code ~= 0 then
    return
  end
  out.commit = vim.trim(obj.stdout)
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
M.confirm = function(prompt)
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

  assert(this_os)
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

--- Adapted from `nvim-orgmode/orgmode`
--- Cycle all headings in file between "Show All", "Contents" and "Overview"
---
M.cycle_global = function()
  local mode = vim.g.obsidian_global_cycle_mode or "Show All"
  if not vim.wo.foldenable or mode == "Show All" then
    mode = "Overview"
    vim.cmd [[silent! norm! zMzX]]
  elseif mode == "Contents" then
    mode = "Show All"
    vim.cmd [[silent! norm! zR]]
  elseif mode == "Overview" then
    mode = "Contents"
    vim.wo.foldlevel = 1
    vim.cmd [[silent! norm! zx]]
  end
  vim.api.nvim_echo({ { "Obsidian: " .. mode } }, false, {})
  vim.g.obsidian_global_cycle_mode = mode
end

---@param bufnr integer
---@param cursor integer[]
---@return TSNode?
local function closest_section_node(bufnr, cursor)
  local parser = ts.get_parser(bufnr, "markdown", {})
  assert(parser)
  local cursor_range = { cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] + 1 }
  local node = parser:named_node_for_range(cursor_range)

  if not node then
    return nil
  end

  if node:type() == "section" then
    return node
  end

  while node and node:type() ~= "section" do
    node = node:parent()
  end

  return node
end

---@param node TSNode
---@return boolean
local function has_child_headlines(node)
  return vim.iter(node:iter_children()):any(function(child)
    return child:type() == "atx_heading"
  end)
end

---@param node TSNode
---@return TSNode[]?
local function get_child_headlines(node)
  local ret = {}
  for child in node:iter_children() do
    if child:type() == "section" then
      ret[#ret + 1] = child
    end
  end
  return ret
end

---@return boolean
local function is_one_line(node)
  local start_row, _, end_row, end_col = node:parent():range()
  -- One line sections have end range on the next line with 0 column
  -- Example: If headline is on line 5, range will be (5, 1, 6, 0)
  return start_row == end_row or (start_row + 1 == end_row and end_col == 0)
end

---@param node TSNode
---@return boolean
local function can_section_expand(node)
  return not is_one_line(node) or has_child_headlines(node)
end

--- Cycle heading state under cursor
M.cycle = function()
  local current_buffer = vim.api.nvim_get_current_buf()
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = vim.fn.line "."

  -- Ensure fold system is active
  if not vim.wo.foldenable then
    vim.wo.foldenable = true
    vim.cmd [[silent! norm! zx]] -- Refresh folds
  end

  -- Check current fold state
  local current_fold_level = vim.fn.foldlevel(current_line)
  if current_fold_level == 0 then
    return
  end

  -- Handle closed folds first
  local is_fold_closed = vim.fn.foldclosed(current_line) ~= -1
  if is_fold_closed then
    return vim.cmd [[silent! norm! zo]] -- Open closed fold
  end

  -- Find Markdown section structure
  local current_section_node = closest_section_node(current_buffer, cursor_position)
  if not current_section_node then
    return
  end

  -- Ignore non-expandable sections
  if not can_section_expand(current_section_node) then
    return
  end

  -- Fold state management
  local child_sections = get_child_headlines(current_section_node)
  local should_close_parent = #child_sections == 0

  if not should_close_parent then
    local has_nested_structure = false

    -- Process child fold states
    for _, child_node in ipairs(child_sections or {}) do
      if can_section_expand(child_node) then
        has_nested_structure = true
        local child_start_line = child_node:start() + 1

        -- Close open child folds first
        if vim.fn.foldclosed(child_start_line) == -1 then
          vim.cmd(string.format("silent! keepjumps norm! %dggzc", child_start_line))
          should_close_parent = true
        end
      end
    end

    -- Return to original cursor position
    vim.cmd(string.format("silent! keepjumps norm! %dgg", current_line))

    -- Close parent if no actual nesting exists
    if not should_close_parent and not has_nested_structure then
      should_close_parent = true
    end
  end

  -- Execute final fold action
  if should_close_parent then
    vim.cmd [[silent! norm! zc]] -- Close parent fold
  else
    vim.cmd [[silent! norm! zczO]] -- Force fold refresh
  end
end

return M
