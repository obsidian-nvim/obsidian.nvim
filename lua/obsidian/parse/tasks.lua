local list_items = require "obsidian.parse.list_items"

local M = {}

---@class obsidian.parse.Task : obsidian.parse.Match
---@field kind "task"
---@field indent integer
---@field marker string
---@field state string
---@field text string

---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.Task[]
function M.extract(line, opts)
  local item = list_items.parse(line, opts)
  if not item or not item.checkbox_state then
    return {}
  end

  ---@type obsidian.parse.Task
  local task = {
    kind = "task",
    raw = line,
    range = item.range,
    indent = item.indent,
    marker = item.marker,
    state = item.checkbox_state,
    text = item.text,
  }

  return { task }
end

return M
