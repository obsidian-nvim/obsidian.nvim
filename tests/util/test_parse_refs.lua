local Range = require "obsidian.range"
local refs = require "obsidian.parse.refs"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses wiki aliases and fragments"] = function()
  local line = "[[Dir/Note#Heading|Label]]"
  eq({
    {
      kind = "wiki",
      raw = line,
      range = Range.new(2, 0, 2, #line),
      target = "Dir/Note",
      label = "Label",
      anchor = "Heading",
      embed = false,
    },
  }, refs.extract(line, { row = 2 }))
end

T["extract parses embeds and block refs"] = function()
  local line = "![[Note#^block-id]]"
  eq({
    {
      kind = "wiki",
      raw = line,
      range = Range.new(0, 0, 0, #line),
      target = "Note",
      block = "block-id",
      embed = true,
    },
  }, refs.extract(line))
end

T["extract returns ranges"] = function()
  local out = refs.extract("See [[A]] and [B](b.md#H)", { row = 2 })
  eq(2, #out)
  eq("A", out[1].target)
  eq(Range.new(2, 4, 2, 9), out[1].range)
  eq("b.md", out[2].target)
  eq("H", out[2].anchor)
  eq(Range.new(2, 14, 2, 25), out[2].range)
end

return T
