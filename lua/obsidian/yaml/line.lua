local util = require "obsidian.util"
local yaml_util = require "obsidian.yaml.util"

---@class obsidian.yaml.Line
---@field content string
---@field raw_content string Content after removing base indentation (legacy parsing view).
---@field source string Original line, without its line ending.
---@field row integer 0-based document row.
---@field content_col integer Byte offset of trimmed content in source.
---@field indent integer
local Line = {}
Line.__index = Line

Line.__tostring = function(self)
  return string.format("Line('%s')", self.raw_content)
end

---Create a new Line instance from a raw line string.
---@param raw_line string
---@param base_indent integer|?
---@param row integer? 0-based document row.
---@return obsidian.yaml.Line
Line.new = function(raw_line, base_indent, row)
  local self = {}
  self.source = raw_line
  self.row = row or 0
  self.content_col = #raw_line - #util.lstrip_whitespace(raw_line)
  self.indent = util.count_indent(raw_line)
  if base_indent ~= nil then
    if base_indent > self.indent and vim.trim(yaml_util.strip_comments(vim.trim(raw_line))) ~= "" then
      error "relative indentation for line is less than base indentation"
    end
    self.indent = math.max(0, self.indent - base_indent)
  end
  self.raw_content = util.lstrip_whitespace(raw_line, base_indent)
  self.content = vim.trim(self.raw_content)
  return setmetatable(self, Line)
end

---Check if a line is empty.
---@param self obsidian.yaml.Line
---@return boolean
Line.is_empty = function(self)
  if yaml_util.strip_comments(self.content) == "" then
    return true
  else
    return false
  end
end

return Line
