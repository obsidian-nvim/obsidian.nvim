local Range = require "obsidian.range"
local tasks = require "obsidian.parse.line.tasks"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses bullet tasks"] = function()
  local line = "  - [x] done"
  local task = tasks.extract(line, { row = 3 })[1]

  eq("task", task.kind)
  eq(line, task.raw)
  eq(Range.new(3, 0, 3, #line), task.range)
  eq(2, task.indent)
  eq("-", task.marker)
  eq("bullet", task.marker_type)
  eq("x", task.state)
  eq("x", task.task_state)
  eq("done", task.text)
  eq(4, task.task_marker_col)
  eq(8, task.text_col)
end

T["extract parses numbered tasks"] = function()
  eq("1.", tasks.extract("1. [ ] open")[1].marker)

  local line = " 2) [-] custom"
  local task = tasks.extract(line)[1]
  eq("2)", task.marker)
  eq("ordered", task.marker_type)
  eq("-", task.state)
  eq("custom", task.text)
  eq(Range.new(0, 0, 0, #line), task.range)
end

T["extract ignores non-tasks"] = function()
  eq({}, tasks.extract "- no checkbox")
  eq({}, tasks.extract "1234567890. [ ] too many digits")
  eq({}, tasks.extract "- - -")
end

return T
