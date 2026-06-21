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

T["extract ignores refs within inline code"] = function()
  local out = refs.extract "`[[Foo]]` [[foo|Bar]]"
  eq(1, #out)
  eq("wiki", out[1].kind)
  eq("foo", out[1].target)
  eq("Bar", out[1].label)
  eq(Range.new(0, 10, 0, 21), out[1].range)
end

T["extract parses footnotes"] = function()
  local out = refs.extract "some claim[^1] and [^note]"
  eq(2, #out)
  eq("footnote", out[1].kind)
  eq("1", out[1].target)
  eq(Range.new(0, 10, 0, 14), out[1].range)
  eq("footnote", out[2].kind)
  eq("note", out[2].target)
  eq(Range.new(0, 19, 0, 26), out[2].range)
end

T["extract parses footnotes in definition lines"] = function()
  local out = refs.extract "[^1]: the footnote text"
  eq(1, #out)
  eq("footnote", out[1].kind)
  eq("1", out[1].target)
  eq(Range.new(0, 0, 0, 4), out[1].range)
end

T["extract prefers footnotes over markdown links"] = function()
  local out = refs.extract "claim[^fn](not a link)"
  eq(1, #out)
  eq("footnote", out[1].kind)
  eq("fn", out[1].target)
  eq(Range.new(0, 5, 0, 10), out[1].range)
end

T["extract does not parse block IDs"] = function()
  eq({}, refs.extract "Paragraph with block ^block-id")
end

T["extract should not match block wiki links as footnotes"] = function()
  local out = refs.extract "[[^block]]"
  eq(1, #out)
  eq("wiki", out[1].kind)
  eq("^block", out[1].target)
  eq(nil, out[1].block)
  eq(Range.new(0, 0, 0, 10), out[1].range)
end

return T
