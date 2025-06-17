local M = require "obsidian.yaml.line"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["should print"] = function()
  local line = M.new "hi"
  eq("Line('hi')", tostring(line))
end

T["should strip spaces and count the indent"] = function()
  local line = M.new "  foo: 1 "
  eq(2, line.indent)
  eq("foo: 1", line.content)
end

T["should strip tabs and count the indent"] = function()
  local line = M.new "		foo: 1"
  eq(2, line.indent)
  eq("foo: 1", line.content)
end

return T
