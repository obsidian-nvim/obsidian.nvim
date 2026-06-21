local Range = require "obsidian.range"
local M = require "obsidian.parse.tags"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local function extract_ranges(line)
  local out = {}
  for _, tag in ipairs(M.extract(line)) do
    out[#out + 1] = { tag.range.start_col + 1, tag.range.end_col }
  end
  return out
end

T["should find positions of all tags"] = function()
  local s = "#TODO I have a #meeting at noon"
  eq({ { 1, 5 }, { 16, 23 } }, extract_ranges(s))
end

T["extract returns tag matches"] = function()
  local s = "#TODO I have a #meeting at noon"
  eq({
    {
      kind = "tag",
      raw = "#TODO",
      range = Range.new(4, 0, 4, 5),
      tag = "TODO",
    },
    {
      kind = "tag",
      raw = "#meeting",
      range = Range.new(4, 15, 4, 23),
      tag = "meeting",
    },
  }, M.extract(s, { row = 4 }))
end

T["should find four cases"] = function()
  eq(1, #M.extract "#camelCase")
  eq(1, #M.extract "#PascalCase")
  eq(1, #M.extract "#snake_case")
  eq(1, #M.extract "#kebab-case")
end

T["should find nested tags"] = function()
  eq(1, #M.extract " #inbox/processing")
  eq(1, #M.extract " #inbox/to-read")
end

T["should ignore escaped tags"] = function()
  local s = "I have a #meeting at noon \\#not-a-tag"
  eq({ { 10, 17 } }, extract_ranges(s))
  s = [[\#notatag]]
  eq({}, M.extract(s))
end

T["should ignore issue numbers"] = function()
  local s = "Issue: #100"
  eq({}, M.extract(s))
end

T["should ignore hexcolors"] = function()
  local s = "background: #f0f0f0"
  eq({}, M.extract(s))
end

T["should ignore anchor links that look like tags"] = function()
  local s = "[readme](README#installation)"
  eq({}, M.extract(s))
end

T["should ignore section in urls"] = function()
  local s = "https://example.com/page#section"
  eq({}, M.extract(s))
end

T["should ignore tags in HTML entities"] = function()
  eq({}, M.extract "Here is an entity: &#NOT_A_TAG;")
end

T["should ignore tags not on word boundaries"] = function()
  eq({}, M.extract "foobar#notatag")
  eq({ { 9, 12 } }, extract_ranges "foo bar #tag")
end

T["should ignore tags in markdown links with parentheses"] = function()
  local s = "[autobox](https://en.wikipedia.org/wiki/Object_type_(object-oriented_programming)#NOT_A_TAG)"
  eq({}, M.extract(s))
end

T["should ignore tags in html comments"] = function()
  local s = "<!-- #region -->"
  eq({}, M.extract(s))
end

T["should find non-English tags"] = function()
  eq(1, #M.extract "#你好")
  eq(1, #M.extract "#タグ")
  eq(1, #M.extract "#mañana")
  eq(1, #M.extract "#день")
  eq(1, #M.extract "#项目_计划")
end

return T
