local Range = require "obsidian.range"
local util = require "obsidian.util"

local M = {}

local PATTERN = "%^[%w%d][%w%d-]*"

--- Normalize a block identifier to its canonical `^id` form.
---@param id string
---@return string
M.normalize = function(id)
  if vim.startswith(id, "#") then
    id = id:sub(2)
  end
  if not vim.startswith(id, "^") then
    id = "^" .. id
  end
  return id
end

--- Parse a naked block ID from the end of a line, excluding inline code.
---@param line string
---@return string?
M.parse = function(line)
  local match = M.extract(line)[1]
  return match and match.raw or nil
end

---Extract a naked block ID from the end of a single line.
---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.line.Match[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local start_col, end_col = line:find(PATTERN .. "$")
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
