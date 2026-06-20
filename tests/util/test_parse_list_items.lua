local Range = require "obsidian.range"
local list_items = require "obsidian.parse.list_items"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses bullet list items"] = function()
  local line = "  * item"
  eq({
    {
      kind = "list_item",
      raw = line,
      range = Range.new(3, 0, 3, #line),
      indent = 2,
      marker = "*",
      marker_type = "bullet",
      text = "item",
    },
  }, list_items.extract(line, { row = 3 }))
end

T["extract parses ordered list items"] = function()
  local item = list_items.extract("  12) item")[1]
  eq("12)", item.marker)
  eq("ordered", item.marker_type)
  eq(12, item.number)
  eq(")", item.delimiter)
  eq("item", item.text)
end

T["extract parses checkbox list items"] = function()
  local item = list_items.extract("- [x] done")[1]
  eq("x", item.checkbox_state)
  eq("done", item.text)
end

T["extract treats empty checkbox body as empty text"] = function()
  eq("", list_items.extract("- [ ]   ")[1].text)
end

T["extract ignores non-list items"] = function()
  eq({}, list_items.extract "not a list")
  eq({}, list_items.extract "1.1 not ordered")
end

return T
