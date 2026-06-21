local Range = require "obsidian.range"
local list_items = require "obsidian.parse.line.list_items"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses bullet list items"] = function()
  local line = "  * item"
  local item = list_items.extract(line, { row = 3 })[1]

  eq("list_item", item.kind)
  eq(line, item.raw)
  eq(Range.new(3, 0, 3, #line), item.range)
  eq(2, item.indent)
  eq("*", item.marker)
  eq("bullet", item.marker_type)
  eq(" ", item.padding)
  eq("item", item.text)
  eq(2, item.marker_col)
  eq(4, item.text_col)
end

T["extract parses ordered list items"] = function()
  local item = list_items.extract("  12) item")[1]
  eq("12)", item.marker)
  eq("ordered", item.marker_type)
  eq(12, item.number)
  eq(")", item.delimiter)
  eq("item", item.text)
end

T["extract allows CommonMark 1-9 digit ordered markers"] = function()
  eq("123456789.", list_items.extract("123456789. ok")[1].marker)
  eq({}, list_items.extract "1234567890. not ok")
end

T["extract parses task list items"] = function()
  local item = list_items.extract("- [x] done")[1]
  eq("x", item.task_state)
  eq("x", item.checkbox_state)
  eq("done", item.text)
  eq(2, item.task_marker_col)
  eq(6, item.text_col)
end

T["extract preserves marker padding before task marker"] = function()
  local item = list_items.extract("-   [ ] indented")[1]
  eq("   ", item.padding)
  eq(" ", item.task_state)
  eq(4, item.task_marker_col)
  eq("indented", item.text)
end

T["extract treats empty list items as empty text"] = function()
  eq("", list_items.extract("-")[1].text)
  eq("", list_items.extract("-   ")[1].text)
  eq("", list_items.extract("2.")[1].text)
end

T["extract treats empty task body as empty text"] = function()
  eq("", list_items.extract("- [ ]   ")[1].text)
end

T["extract ignores non-list items"] = function()
  eq({}, list_items.extract "not a list")
  eq({}, list_items.extract "-not a list")
  eq({}, list_items.extract "1.1 not ordered")
  eq({}, list_items.extract "1)1 not ordered")
end

T["extract lets thematic breaks take precedence over list items"] = function()
  eq({}, list_items.extract "- - -")
  eq({}, list_items.extract "***")
  eq({}, list_items.extract "  * * *  ")
end

return T
