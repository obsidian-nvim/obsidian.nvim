local M = require "obsidian.yaml.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["comments"] = new_set()

T["comments"]["should strip comments from a string"] = function()
  eq("foo: 1", M.strip_comments "foo: 1  # this is a comment")
end

T["comments"]["should strip comments even when they start at the beginning of the string"] = function()
  eq("", M.strip_comments "# foo: 1")
end

T["comments"]["should ignore '#' when enclosed in quotes"] = function()
  eq([["hashtags start with '#'"]], M.strip_comments [["hashtags start with '#'"]])
end

T["comments"]["should ignore an escaped '#'"] = function()
  eq([[hashtags start with \# right?]], M.strip_comments [[hashtags start with \# right?]])
end

T["next_item"] = new_set()

T["next_item"]["should pull out next list item with enclosing quotes"] = function()
  eq('"foo"', M.next_item([=["foo", "bar"]=], { "," }))
end

T["next_item"]["should pull out the last list item with enclosing quotes"] = function()
  eq('"foo"', M.next_item([=["foo"]=], { "," }))
end

T["next_item"]["should pull out the last list item with enclosing quotes and stop char"] = function()
  eq('"foo"', M.next_item([=["foo",]=], { "," }))
end

T["next_item"]["should pull out next list item without enclosing quotes"] = function()
  eq("foo", M.next_item([=[foo, "bar"]=], { "," }))
end

T["next_item"]["should pull out next list item even when the item contains the stop char"] = function()
  eq('"foo, baz"', M.next_item([=["foo, baz", "bar"]=], { "," }))
end

T["next_item"]["should pull out the last list item without enclosing quotes"] = function()
  eq("foo", M.next_item([=[foo]=], { "," }))
end

T["next_item"]["should pull out the last list item without enclosing quotes and stop char"] = function()
  eq("foo", M.next_item([=[foo,]=], { "," }))
end

T["next_item"]["should pull nested array"] = function()
  eq("[foo, bar]", M.next_item("[foo, bar],", { "]" }, true))
end

T["next_item"]["should pull out the key in an array"] = function()
  local next_item, str = M.next_item("foo: bar", { ":" }, false)
  eq("foo", next_item)
  eq(" bar", str)
  next_item, str = M.next_item("bar: 1, baz: 'Baz'", { ":" }, false)
  eq("bar", next_item)
  eq(" 1, baz: 'Baz'", str)
end

return T
