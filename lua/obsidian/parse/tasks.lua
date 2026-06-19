local Range = require "obsidian.range"

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
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local indent, marker, state, text = line:match "^(%s*)([-%*%+]) %[(.)%] (.*)$"
  if not state then
    indent, marker, state, text = line:match "^(%s*)(%d+[%.%)]) %[(.)%] (.*)$"
  end

  if not state then
    return {}
  end
  ---@cast indent string
  ---@cast marker string
  ---@cast state string
  ---@cast text string

  ---@type obsidian.parse.Task
  local task = {
    kind = "task",
    raw = line,
    range = Range.new(row, 0, row, #line),
    indent = #indent,
    marker = marker,
    state = state,
    text = text,
  }

  return { task }
end

return M
