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

T["extract enforces surrounding whitespace grammar"] = function()
  local matches = highlight.extract "outside ==valid== whitespace == leading== ==trailing =="
  eq(1, #matches)
  eq("valid", matches[1].text)
end

T["extract parses adjacent highlights"] = function()
  local matches = highlight.extract "==one====two=="
  eq(2, #matches)
  eq("one", matches[1].text)
  eq("two", matches[2].text)
  eq(Range.new(0, 0, 0, 7), matches[1].range)
  eq(Range.new(0, 7, 0, 14), matches[2].range)
end

T["extract allows a single equals sign in highlighted text"] = function()
  local match = highlight.extract("==one=two==")[1]
  eq("one=two", match.text)
  eq("==one=two==", match.raw)
end

T["extract rejects empty highlights"] = function()
  eq({}, highlight.extract "before ==== after")
end

T["extract ranges use byte columns for Unicode"] = function()
  local match = highlight.extract("é ==你好==", { row = 4 })[1]
  eq("你好", match.text)
  eq(Range.new(4, 3, 4, 13), match.range)
end

T["find_highlight preserves its legacy shape"] = function()
  eq({ { 1, 17, "🔴Important" } }, search.find_highlight "==🔴Important==")
end

return T
