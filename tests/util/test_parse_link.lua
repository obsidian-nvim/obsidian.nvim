local refs = require "obsidian.parse.refs"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["parses note block destinations"] = function()
  local ref = assert(refs.parse "[[hi#^block]]")
  eq("hi", ref.target)
  eq(nil, ref.anchor)
  eq("block", ref.block)
end

T["header link"] = new_set()

T["header link"]["parses wiki links"] = function()
  local ref = assert(refs.parse "[[#Header]]")
  eq("", ref.target)
  eq("Header", ref.anchor)
  eq(nil, ref.label)
  eq("wiki", ref.kind)
end

T["header link"]["parses wiki aliases"] = function()
  local ref = assert(refs.parse "[[#header|Header]]")
  eq("", ref.target)
  eq("header", ref.anchor)
  eq("Header", ref.label)
end

T["header link"]["parses Markdown links"] = function()
  local ref = assert(refs.parse "[Header](#header)")
  eq("", ref.target)
  eq("header", ref.anchor)
  eq("Header", ref.label)
  eq("markdown", ref.kind)
end

T["block link"] = new_set()

T["block link"]["parses wiki links"] = function()
  local ref = assert(refs.parse "[[#^block]]")
  eq("", ref.target)
  eq("block", ref.block)
  eq("wiki", ref.kind)
end

T["block link"]["parses wiki aliases"] = function()
  local ref = assert(refs.parse "[[#^block|Block]]")
  eq("", ref.target)
  eq("block", ref.block)
  eq("Block", ref.label)
end

T["block link"]["parses Markdown links"] = function()
  local ref = assert(refs.parse "[Block](#^block)")
  eq("", ref.target)
  eq("block", ref.block)
  eq("Block", ref.label)
  eq("markdown", ref.kind)
end

T["wiki table escapes"] = function()
  local ref = assert(refs.parse [=[[[note\|Label]]]=])
  eq("note", ref.target)
  eq("Label", ref.label)
end

return T
