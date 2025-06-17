local util = require "obsidian.util"

---@class obsidian.yaml.Line : obsidian.ABC
---@field content string
---@field raw_content string
---@field indent integer
local M = {}
M.__index = M

M.__tostring = function(self)
  return string.format("Line('%s')", self.content)
end

---Create a new Line instance from a raw line string.
---@param raw_line string
---@param base_indent integer|?
---@return obsidian.yaml.Line
M.new = function(raw_line, base_indent)
  local t = {}
  t.indent = util.count_indent(raw_line)
  if base_indent ~= nil then
    if base_indent > t.indent then
      error "relative indentation for line is less than base indentation"
    end
    t.indent = t.indent - base_indent
  end
  t.raw_content = util.lstrip_whitespace(raw_line, base_indent)
  t.content = vim.trim(t.raw_content)
  return setmetatable(t, M)
end

---Check if a line is empty.
---@param self obsidian.yaml.Line
---@return boolean
M.is_empty = function(self)
  if util.strip_comments(self.content) == "" then
    return true
  else
    return false
  end
end

return M
