local tasks = require "obsidian.parse.tasks"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["match_task parses bullet tasks"] = function()
  eq({ indent = 2, state = "x", text = "done" }, tasks.match_task("  - [x] done"))
end

T["match_task parses numbered tasks"] = function()
  eq({ indent = 0, state = " ", text = "open" }, tasks.match_task("1. [ ] open"))
  eq({ indent = 1, state = "-", text = "custom" }, tasks.match_task(" 2) [-] custom"))
end

T["match_task ignores non-tasks"] = function()
  eq(nil, tasks.match_task("- no checkbox"))
end

return T
