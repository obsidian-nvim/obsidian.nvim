local api = require "obsidian.api"
local log = require "obsidian.log"
local picker = require "obsidian.picker"

local M = {}

---@class obsidian.footnote.Definition
---@field id string footnote id, without the leading "^"
---@field lnum integer 1-indexed line number of the definition
---@field text string definition content (text after the colon)

---@class obsidian.footnote.Ref
---@field lnum integer 1-indexed line number
---@field start_col integer 0-indexed start column
---@field end_col integer 0-indexed exclusive end column

---Parse a footnote definition line like `[^1]: some text`.
---
---@param line string
---@return string? id
---@return string? text
M.parse_definition = function(line)
  return line:match "^%[%^([^%]%[%s]+)%]:%s*(.*)$"
end

---Collect all footnote definitions in a buffer.
---
---@param bufnr integer|?
---@return obsidian.footnote.Definition[]
M.definitions = function(bufnr)
  bufnr = bufnr or 0
  ---@type obsidian.footnote.Definition[]
  local defs = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local id, text = M.parse_definition(line)
    if id and text then
      defs[#defs + 1] = { id = id, lnum = lnum, text = text }
    end
  end
  return defs
end

-- TODO: power hover
---Find the definition for a given footnote id.
---
---@param bufnr integer|?
---@param id string
---@return obsidian.footnote.Definition|?
M.find_definition = function(bufnr, id)
  for _, def in ipairs(M.definitions(bufnr)) do
    if def.id == id then
      return def
    end
  end
end

---Find all occurrences of `[^id]` in a buffer, including the definition line.
---
---@param bufnr integer|?
---@param id string
---@return obsidian.footnote.Ref[]
M.find_refs = function(bufnr, id)
  bufnr = bufnr or 0
  ---@type obsidian.footnote.Ref[]
  local refs = {}
  local pattern = "%[%^" .. vim.pesc(id) .. "%]"
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local init = 1
    while true do
      local m_start, m_end = line:find(pattern, init)
      if not m_start or not m_end then
        break
      end
      refs[#refs + 1] = { lnum = lnum, start_col = m_start - 1, end_col = m_end }
      init = m_end + 1
    end
  end
  return refs
end

---Append a footnote definition to the end of the buffer.
---
---@param bufnr integer
---@param id string
---@param text string
M.insert_definition = function(bufnr, id, text)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

  local new_lines = {}
  if last_line and vim.trim(last_line) ~= "" then
    new_lines[#new_lines + 1] = ""
  end
  new_lines[#new_lines + 1] = ("[^%s]: %s"):format(id, text)

  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, new_lines)
end

---Create a footnote definition, prompting for its content.
---
---@param id string|?
---@param bufnr integer|?
---@param restore_cursor [integer, integer]|?
M.create = function(id, bufnr, restore_cursor)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local function restore_completion_cursor()
    if restore_cursor and vim.api.nvim_get_current_buf() == bufnr then
      if pcall(vim.api.nvim_win_set_cursor, 0, restore_cursor) then
        vim.cmd "startinsert!"
      end
    end
  end

  if not id or id == "" then
    id = api.input "Footnote id"
    if not id or id == "" then
      return log.warn "Aborted"
    end
  end

  local def = M.find_definition(bufnr, id)
  if def then
    restore_completion_cursor()
    return log.info("Footnote [^%s] already defined on line %d", id, def.lnum)
  end

  local text = api.input(("[^%s]"):format(id))
  if not text then
    restore_completion_cursor()
    return log.warn "Aborted"
  end

  M.insert_definition(bufnr, id, text)
  restore_completion_cursor()
end

---Show all footnotes of the current note via picker.
---
---@param bufnr integer|?
M.pick = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local defs = M.definitions(bufnr)

  if vim.tbl_isempty(defs) then
    return log.info "No footnotes in current note"
  end

  local note_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  ---@param def obsidian.footnote.Definition
  ---@return obsidian.ui.select_preview_spec
  local function preview_footnote(def)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, note_lines)
    vim.bo[buf].filetype = "markdown"
    return { buf = buf, pos = { def.lnum, 0 } }
  end

  ---@param def obsidian.footnote.Definition
  ---@return string
  local function format_footnote(def)
    return ("[^%s]: %s"):format(def.id, def.text)
  end

  picker.select(defs, {
    prompt = "Footnotes",
    format_item = format_footnote,
    preview_item = preview_footnote,
  }, function(items)
    local def = items[1]
    if def then
      vim.api.nvim_win_set_cursor(0, { def.lnum, 0 })
    end
  end)
end

return M
