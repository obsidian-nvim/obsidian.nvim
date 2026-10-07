local Range = require "obsidian.range"
local highlight = require "obsidian.parse.highlight"
local search = require "obsidian.search"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses highlights"] = function()
  local line = "before ==hello== after"
  local match = highlight.extract(line, { row = 2 })[1]

  eq("highlight", match.kind)
  eq("==hello==", match.raw)
  eq("hello", match.text)
  eq(nil, match.color)
  eq(Range.new(2, 7, 2, 16), match.range)
end

T["extract parses color emojis"] = function()
  local match = highlight.extract("==🔴Important==")[1]

  eq("Important", match.text)
  eq("red", match.color)
end

T["extract ignores highlights with surrounding whitespace"] = function()
  eq({}, highlight.extract "== leading== ==trailing ==")
end

T["find_highlight preserves its legacy shape"] = function()
  eq({ { 1, 17, "🔴Important" } }, search.find_highlight "==🔴Important==")
end

return T
