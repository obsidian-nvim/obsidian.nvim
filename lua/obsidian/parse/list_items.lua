local Range = require "obsidian.range"

local M = {}

---@alias obsidian.parse.ListMarkerType "bullet"|"ordered"

---@class obsidian.parse.ListItem : obsidian.parse.Match
---@field kind "list_item"
---@field indent integer
---@field marker string
---@field marker_type obsidian.parse.ListMarkerType
---@field delimiter string?
---@field number integer?
---@field text string
---@field checkbox_state string?

---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.ListItem[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local indent, marker, rest = line:match "^(%s*)([-%*%+])%s+(.*)$"
  local marker_type = "bullet"
  local delimiter
  ---@type integer?
  local number

  if not marker then
    local number_str
    indent, number_str, delimiter, rest = line:match "^(%s*)(%d+)([%.%)])%s+(.*)$"
    if number_str then
      number = tonumber(number_str)
      ---@cast number integer
      marker = number_str .. delimiter
      marker_type = "ordered"
    end
  end

  if not marker then
    return {}
  end
  ---@cast indent string
  ---@cast marker string
  ---@cast marker_type obsidian.parse.ListMarkerType
  ---@cast rest string

  local checkbox_state, checkbox_text = rest:match "^%[(.)%]%s*(.*)$"
  local text = checkbox_state and checkbox_text or rest

  ---@type obsidian.parse.ListItem
  local item = {
    kind = "list_item",
    raw = line,
    range = Range.new(row, 0, row, #line),
    indent = #indent,
    marker = marker,
    marker_type = marker_type,
    delimiter = delimiter,
    number = number,
    text = text,
    checkbox_state = checkbox_state,
  }

  return { item }
end

---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.ListItem?
function M.parse(line, opts)
  return M.extract(line, opts)[1]
end

return M
