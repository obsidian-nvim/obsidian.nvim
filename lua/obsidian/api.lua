local M = {}
local util = require "obsidian.util"
local log = require "obsidian.log"
local iter, string, table = vim.iter, string, table

---builtin functions that are impure, interacts with editor state, like vim.api

---Toggle the checkbox on the current line.
---
---@param opts table|nil Optional table containing checkbox states (e.g., {" ", "x"}).
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.toggle_checkbox = function(opts, line_num)
  -- Allow line_num to be optional, defaulting to the current line if not provided
  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  local checkboxes = opts or { " ", "x" }

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
  -- 0-indexed
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

  local current_line = line and line or vim.api.nvim_get_current_line()
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
  opts = opts and opts or {}

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

---Insert text at current cursor position.
---@param text string
M.insert_text = function(text)
  local curpos = vim.fn.getcurpos()
  local line_num, line_col = curpos[2], curpos[3]
  local indent = string.rep(" ", line_col)

  -- Convert text to lines table so we can handle multi-line strings.
  local lines = {}
  for line in text:gmatch "[^\r\n]+" do
    lines[#lines + 1] = line
  end

  for line_index, line in pairs(lines) do
    local current_line_num = line_num + line_index - 1
    local current_line = vim.fn.getline(current_line_num)
    assert(type(current_line) == "string")

    -- Since there's no column 0, remove extra space when current line is blank.
    if current_line == "" then
      indent = indent:sub(1, -2)
    end

    local pre_txt = current_line:sub(1, line_col)
    local post_txt = current_line:sub(line_col + 1, -1)
    local inserted_txt = pre_txt .. line .. post_txt

    vim.fn.setline(current_line_num, inserted_txt)

    -- Create new line so inserted_txt doesn't replace next lines
    if line_index ~= #lines then
      vim.fn.append(current_line_num, indent)
    end
  end
end

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

---Get the path to where a plugin is installed.
---@param name string|?
---@return string|?
local get_src_root = function(name)
  name = name and name or "obsidian.nvim"
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.endswith(path, name) then
      return path
    end
  end
  return nil
end

--- Get info about a plugin.
---
---@param name string|?
---
---@return { commit: string|?, path: string }|?
M.get_plugin_info = function(name)
  name = name and name or "obsidian.nvim"

  local src_root = get_src_root(name)
  if src_root == nil then
    return nil
  end

  local out = { path = src_root }

  local Job = require "plenary.job"
  local output, exit_code = Job:new({ ---@diagnostic disable-line: missing-fields
    command = "git",
    args = { "rev-parse", "HEAD" },
    cwd = src_root,
    enable_recording = true,
  }):sync(1000)

  if exit_code == 0 then
    out.commit = output[1]
  end

  return out
end

---@param cmd string
---@return string|?
M.get_external_dependency_info = function(cmd)
  local Job = require "plenary.job"
  local output, exit_code = Job:new({ ---@diagnostic disable-line: missing-fields
    command = cmd,
    args = { "--version" },
    enable_recording = true,
  }):sync(1000)

  if exit_code == 0 then
    return output[1]
  end
end

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

return M
