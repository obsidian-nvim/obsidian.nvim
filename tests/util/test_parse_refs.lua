local refs = require "obsidian.parse.refs"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["parse_ref parses wiki aliases and fragments"] = function()
  eq({
    kind = "wiki",
    raw = "[[Dir/Note#Heading|Label]]",
    target = "Dir/Note",
    label = "Label",
    anchor = "Heading",
    embed = false,
  }, refs.parse_ref("[[Dir/Note#Heading|Label]]", "WikiWithAlias"))
end

T["parse_ref parses embeds and block refs"] = function()
  eq({
    kind = "wiki",
    raw = "![[Note#^block-id]]",
    target = "Note",
    block = "block-id",
    embed = true,
  }, refs.parse_ref("![[Note#^block-id]]", "Wiki"))
end

T["extract_links returns positions"] = function()
  local out = refs.extract_links("See [[A]] and [B](b.md#H)", 3)
  eq(2, #out)
  eq("A", out[1].target)
  eq(5, out[1].col)
  eq(3, out[1].line)
  eq("b.md", out[2].target)
  eq("H", out[2].anchor)
end

return T
