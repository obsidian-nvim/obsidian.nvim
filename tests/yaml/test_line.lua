local Line = require "obsidian.yaml.line"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["line"] = new_set()

T["line"]["should strip spaces and count the indent"] = function()
  local line = Line.new "  foo: 1 "
  eq(2, line.indent)
  eq("foo: 1", line.content)
end

T["line"]["should strip tabs and count the indent"] = function()
  local line = Line.new "		foo: 1"
  eq(2, line.indent)
  eq("foo: 1", line.content)
end

return T
