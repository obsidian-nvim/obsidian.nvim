local Range = require "obsidian.range"

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

--- Parse a naked block ID from the end of a line.
---@param line string
---@return string?
M.parse = function(line)
  local match = M.extract(line)[1]
  return match and match.raw or nil
end

--- Extract a naked block ID from the end of a line. By default this applies
--- standalone document filtering; set `opts.lexical` when a full-document
--- consumer will apply filtering against its shared snapshot.
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

  local matches = {
    {
      raw = line:sub(start_col, end_col),
      range = Range.new(row, start_col - 1, row, end_col),
    },
  }
  if opts.lexical then
    return matches
  end

  local Document = require "obsidian.parse.document"
  local document = Document.parse { line }
  local range = Range.new(0, start_col - 1, 0, end_col)
  if document:intersects(range, Document.BODY_EXCLUSIONS) then
    return {}
  end
  return matches
end

return M
