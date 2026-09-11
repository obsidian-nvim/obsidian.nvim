local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"

local M = {}

---@param request obsidian.completion.Request
---@param start_col integer
---@param end_col integer
---@return boolean
M.trigger_is_excluded = function(request, start_col, end_col)
  if request.bufnr ~= nil and request.line ~= nil then
    local document = BufferDocument.get(request.bufnr)
    local source_line = document.lines[request.line + 1]
    if source_line and end_col <= #source_line then
      return document:intersects(Range.new(request.line, start_col, request.line, end_col), Document.BODY_EXCLUSIONS)
    end
  end
  local line = request.cursor_before_line .. request.cursor_after_line
  local document = Document.parse { line }
  end_col = math.min(end_col, #line)
  start_col = math.min(start_col, end_col)
  return document:intersects(Range.new(0, start_col, 0, end_col), Document.BODY_EXCLUSIONS)
end

return M
