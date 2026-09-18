--- Compatibility wrapper for the legacy line tag parser.
local tags = require "obsidian.parse.tags"

local M = {}

--- Find eligible Obsidian-style tags in a standalone Markdown line.
--- Byte indices are 1-based and end-inclusive.
---@param line string
---@return { [1]: integer, [2]: integer }[]
M.parse_tags = function(line)
  local result = {}
  for _, tag in ipairs(tags.extract(line)) do
    result[#result + 1] = { tag.range.start_col + 1, tag.range.end_col }
  end
  return result
end

return M
