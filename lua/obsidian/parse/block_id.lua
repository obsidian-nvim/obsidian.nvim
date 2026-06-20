local Range = require "obsidian.range"
local util = require "obsidian.util"

local M = {}

---Extract a naked block ID from the end of a single line.
---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.Match[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local start_col, end_col = line:find(util.BLOCK_PATTERN .. "$")
  if not start_col or not end_col then
    return {}
  end

  for code_start, code_end in util.gfind(line, "`[^`]*`") do
    if code_start < start_col and end_col < code_end then
      return {}
    end
  end

  return {
    {
      raw = line:sub(start_col, end_col),
      range = Range.new(row, start_col - 1, row, end_col),
    },
  }
end

return M
