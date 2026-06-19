local list_items = require "obsidian.parse.list_items"
local util = require "obsidian.util"

local M = {}

---@alias obsidian.outline.Direction "above"|"below"
---@alias obsidian.outline.Mode "i"|"n"

---@class obsidian.outline.Continuation
---@field line string? New line content to insert.
---@field clear_current string? Replacement for current line before inserting a new line.

local function in_ignored_node()
  return util.in_node {
    "fenced_code_block",
    "minus_metadata",
  }
end

---@param direction string?
---@return obsidian.outline.Direction
local function normalize_direction(direction)
  if direction == "above" then
    return "above"
  end
  return "below"
end

---@param line string
---@param item obsidian.parse.ListItem
---@param direction obsidian.outline.Direction?
---@return string
local function marker_prefix(line, item, direction)
  local indent = line:match "^(%s*)" or ""
  if item.marker_type == "ordered" then
    local n = item.number or 1
    if direction == "below" then
      n = n + 1
    end
    return indent .. tostring(n) .. (item.delimiter or ".") .. " "
  end
  return indent .. item.marker .. " "
end

---Return outline continuation info for a list item line.
---
---For downward continuations, empty list items are cleared instead of continued.
---Checkbox continuations preserve the marker and reset the checkbox state to unchecked.
---
---@param line string
---@param opts { direction: obsidian.outline.Direction?, col: integer? }?
---@return obsidian.outline.Continuation?
function M._get_continuation(line, opts)
  opts = opts or {}
  local direction = normalize_direction(opts.direction)
  if opts.col and opts.col <= #line then
    return nil
  end

  local item = list_items.parse(line)
  if not item then
    return nil
  end

  local marker = marker_prefix(line, item, direction)
  if item.text == "" and direction == "below" then
    if item.checkbox_state then
      return { clear_current = marker_prefix(line, item) }
    end
    return { clear_current = line:match "^(%s*)" or "" }
  end

  if item.checkbox_state then
    return { line = marker .. "[ ] " }
  end
  return { line = marker }
end

---@param direction obsidian.outline.Direction
---@param mode obsidian.outline.Mode
local function fallback(direction, mode)
  if mode == "i" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, true, true), "n", true)
  elseif normalize_direction(direction) == "above" then
    vim.cmd "normal! O"
  else
    vim.cmd "normal! o"
  end
end

---Continue a Markdown list item above or below the cursor.
---
---Intended for opt-in mappings of insert `<CR>` and normal `o`/`O`.
---Falls back to the original key when the current line is not a list item.
---
---@param direction obsidian.outline.Direction? Defaults to "below".
---@param mode obsidian.outline.Mode? Defaults to current mode.
function M.continue(direction, mode)
  direction = normalize_direction(direction)
  mode = mode or (vim.fn.mode():sub(1, 1) == "i" and "i" or "n")
  ---@cast direction obsidian.outline.Direction
  ---@cast mode obsidian.outline.Mode

  if not Obsidian.opts.outline.enabled or in_ignored_node() then
    return fallback(direction, mode)
  end

  local line = vim.api.nvim_get_current_line()
  local col
  if mode == "i" then
    col = vim.api.nvim_win_get_cursor(0)[2] + 1
  end

  local info = M._get_continuation(line, { direction = direction, col = col })
  if not info then
    return fallback(direction, mode)
  end

  if info.clear_current then
    vim.api.nvim_set_current_line(info.clear_current)
  end

  if mode == "i" then
    local keys = "<CR>" .. (info.line or "")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "n", true)
  else
    fallback(direction, mode)
    if info.line then
      vim.api.nvim_set_current_line(info.line)
      vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], #info.line })
    end
  end
end

return M
