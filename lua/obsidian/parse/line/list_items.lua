local Range = require "obsidian.range"

local M = {}

-- Line-level helper for a list marker at the current container offset.
-- It intentionally accepts any leading spaces/tabs; a block parser should
-- decide whether that indentation starts/nests a CommonMark list item.

---@alias obsidian.parse.line.ListMarkerType "bullet"|"ordered"

---@class obsidian.parse.line.ListItem : obsidian.parse.line.Match
---@field kind "list_item"
---@field indent integer Marker byte column after leading spaces/tabs.
---@field marker string Full list marker, e.g. `-`, `1.`, or `2)`.
---@field marker_type obsidian.parse.line.ListMarkerType
---@field delimiter string? Ordered list marker delimiter, either `.` or `)`.
---@field number integer? Ordered list marker number.
---@field padding string Spaces/tabs between the list marker and item text.
---@field text string Item text after marker padding and optional task marker.
---@field task_state string? Obsidian/GFM task marker state from `[x]`.
---@field checkbox_state string? Deprecated alias for `task_state`.
---@field marker_col integer 0-based marker start byte column.
---@field text_col integer 0-based text start byte column.
---@field task_marker_col integer? 0-based task marker start byte column.

local function is_space_or_tab(char)
  return char == " " or char == "\t"
end

---CommonMark thematic break detection.
---A thematic break takes precedence over a list item.
---@param line string
---@return boolean
local function is_thematic_break(line)
  local body = line:match "^[ \t]*(.-)[ \t]*$"
  if not body or body == "" then
    return false
  end

  for _, marker in ipairs { "-", "*", "_" } do
    local count = 0
    local ok = true
    for i = 1, #body do
      local char = body:sub(i, i)
      if char == marker then
        count = count + 1
      elseif not is_space_or_tab(char) then
        ok = false
        break
      end
    end
    if ok and count >= 3 then
      return true
    end
  end

  return false
end

---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.line.ListItem[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  if is_thematic_break(line) then
    return {}
  end

  local indent, marker, padding, rest = line:match "^([ \t]*)([-%*%+])([ \t]*)(.*)$"
  local marker_type = "bullet"
  local delimiter
  ---@type integer?
  local number

  if marker and padding == "" and rest ~= "" then
    marker = nil
  end

  if not marker then
    local number_str
    indent, number_str, delimiter, padding, rest = line:match "^([ \t]*)(%d+)([%.%)])([ \t]*)(.*)$"
    if number_str and #number_str <= 9 and (padding ~= "" or rest == "") then
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
  ---@cast marker_type obsidian.parse.line.ListMarkerType
  ---@cast padding string
  ---@cast rest string

  local text = rest
  local task_state, task_padding, task_text = rest:match "^%[(.)%]([ \t]*)(.*)$"
  if task_state then
    text = task_text
  end

  local marker_col = #indent
  local content_col = marker_col + #marker + #padding
  local text_col = content_col
  if task_state then
    text_col = content_col + 3 + #task_padding
  end

  ---@type obsidian.parse.line.ListItem
  local item = {
    kind = "list_item",
    raw = line,
    range = Range.new(row, 0, row, #line),
    indent = marker_col,
    marker = marker,
    marker_type = marker_type,
    delimiter = delimiter,
    number = number,
    padding = padding,
    text = text,
    task_state = task_state,
    checkbox_state = task_state,
    marker_col = marker_col,
    text_col = text_col,
    task_marker_col = task_state and content_col or nil,
  }

  return { item }
end

---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.line.ListItem?
function M.parse(line, opts)
  return M.extract(line, opts)[1]
end

return M
