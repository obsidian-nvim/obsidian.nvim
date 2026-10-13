local Footnotes = require "obsidian.completion.footnotes"
local Refs = require "obsidian.completion.refs"
local Tags = require "obsidian.completion.tags"

local M = {}
local states = {}

---@param bufnr integer
---@return obsidian.completion.Request|?
local function cursor_request(bufnr)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
    or vim.api.nvim_get_current_buf() ~= bufnr
  then
    return nil
  end

  local ok, mode = pcall(vim.fn.mode, 1)
  if not ok or type(mode) ~= "string" or mode:sub(1, 1) ~= "i" then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local character = cursor[2]
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""

  return {
    bufnr = bufnr,
    cursor_before_line = line_text:sub(1, character),
    cursor_after_line = line_text:sub(character + 1),
    line = line,
    character = character,
  }
end

---@param bufnr integer
---@return boolean
local function is_active(bufnr)
  local request = cursor_request(bufnr)
  if not request then
    return false
  end

  if Refs.can_complete(request, { allow_empty = true }) then
    return true
  end

  local can_complete_tag, _, in_frontmatter = Tags.can_complete(request, { allow_empty = true })
  if can_complete_tag and not in_frontmatter then
    return true
  end

  return Footnotes.can_complete(request) == true
end

---Observe whether the cursor is in a built-in completion expression.
---@param bufnr integer
---@return boolean active
---@return boolean left Whether this observation transitioned from active to inactive.
M.observe = function(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local active = is_active(bufnr)
  local left = states[bufnr] == true and not active
  states[bufnr] = active
  return active, left
end

return M
