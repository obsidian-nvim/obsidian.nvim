local M = {}
local util = require "obsidian.util"
local iter = vim.iter

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
  return M.parse_link(link, {
    link_type = link_type,
    include_naked_urls = opts.include_naked_urls,
    include_file_urls = opts.include_file_urls,
    include_block_ids = opts.include_block_ids,
  })
end

---@param link string
---@param opts { include_naked_urls: boolean|?, include_file_urls: boolean|?, include_block_ids: boolean|?, link_type: obsidian.search.RefTypes|? }|?
---
---@return string|?, string|?, obsidian.search.RefTypes|?
M.parse_link = function(link, opts)
  local search = require "obsidian.search"

  opts = opts and opts or {}

  local link_type = opts.link_type
  if link_type == nil then
    for match in
      iter(search.find_refs(link, {
        include_naked_urls = opts.include_naked_urls,
        include_file_urls = opts.include_file_urls,
        include_block_ids = opts.include_block_ids,
      }))
    do
      local _, _, m_type = unpack(match)
      if m_type then
        link_type = m_type
        break
      end
    end
  end

  if link_type == nil then
    return nil
  end

  local link_location, link_name
  if link_type == search.RefTypes.Markdown then
    link_location = link:gsub("^%[(.-)%]%((.*)%)$", "%2")
    link_name = link:gsub("^%[(.-)%]%((.*)%)$", "%1")
  elseif link_type == search.RefTypes.NakedUrl then
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.FileUrl then
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.WikiWithAlias then
    link = util.unescape_single_backslash(link)
    -- remove boundary brackets, e.g. '[[XXX|YYY]]' -> 'XXX|YYY'
    link = link:sub(3, #link - 2)
    -- split on the "|"
    local split_idx = link:find "|"
    link_location = link:sub(1, split_idx - 1)
    link_name = link:sub(split_idx + 1)
  elseif link_type == search.RefTypes.Wiki then
    -- remove boundary brackets, e.g. '[[YYY]]' -> 'YYY'
    link = link:sub(3, #link - 2)
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.BlockID then
    link_location = util.standardize_block(link)
    link_name = link
  else
    error("not implemented for " .. link_type)
  end

  return link_location, link_name, link_type
end

--- Get the tag under the cursor, if there is one.
---
---@param line string|?
---@param col integer|?
---
---@return string|?
M.cursor_tag = function(line, col)
  local search = require "obsidian.search"

  local current_line = line and line or vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = col or cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for match in iter(search.find_tags(current_line)) do
    local open, close, _ = unpack(match)
    if open <= cur_col and cur_col <= close then
      return string.sub(current_line, open + 1, close)
    end
  end

  return nil
end

--- Get the heading under the cursor, if there is one.
---
---@param line string|?
---
---@return string|?
M.cursor_heading = function(line)
  local current_line = line and line or vim.api.nvim_get_current_line()
  return current_line:match "^(%s*)(#+)%s*(.*)$"
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
