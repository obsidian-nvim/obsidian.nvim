local Range = require "obsidian.range"
local tasks = require "obsidian.parse.tasks"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses bullet tasks"] = function()
  local line = "  - [x] done"
  eq({
    {
      kind = "task",
      raw = line,
      range = Range.new(3, 0, 3, #line),
      indent = 2,
      marker = "-",
      state = "x",
      text = "done",
    },
  }, tasks.extract(line, { row = 3 }))
end

T["extract parses numbered tasks"] = function()
  eq("1.", tasks.extract("1. [ ] open")[1].marker)

  local line = " 2) [-] custom"
  eq({
    {
      kind = "task",
      raw = line,
      range = Range.new(0, 0, 0, #line),
      indent = 1,
      marker = "2)",
      state = "-",
      text = "custom",
    },
  }, tasks.extract(line))
end

T["extract ignores non-tasks"] = function()
  eq({}, tasks.extract "- no checkbox")
end

return T
