local list_items = require "obsidian.parse.line.list_items"

local M = {}

---@class obsidian.parse.line.Task : obsidian.parse.line.Match
---@field kind "task"
---@field indent integer Marker byte column after leading spaces/tabs.
---@field marker string Full list marker, e.g. `-`, `1.`, or `2)`.
---@field marker_type obsidian.parse.line.ListMarkerType
---@field state string Deprecated alias for `task_state`.
---@field task_state string Obsidian/GFM task marker state from `[x]`.
---@field text string Task text after the task marker.
---@field task_marker_col integer 0-based task marker start byte column.
---@field text_col integer 0-based text start byte column.

---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.line.Task[]
function M.extract(line, opts)
  local item = list_items.parse(line, opts)
  if not item or not item.task_state then
    return {}
  end

  ---@type obsidian.parse.line.Task
  local task = {
    kind = "task",
    raw = line,
    range = item.range,
    indent = item.indent,
    marker = item.marker,
    marker_type = item.marker_type,
    state = item.task_state,
    task_state = item.task_state,
    text = item.text,
    task_marker_col = item.task_marker_col,
    text_col = item.text_col,
  }

  return { task }
end

return M
