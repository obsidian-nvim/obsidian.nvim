local M = require "obsidian.parse.tags"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()
T["find_tags_in_string"] = new_set()

T["find_tags_in_string"]["should find positions of all tags"] = function()
  local s = "#TODO I have a #meeting at noon"
  eq({ { 1, 5, "Tag" }, { 16, 23, "Tag" } }, M.parse_tags(s))
end

T["find_tags_in_string"]["should find four cases"] = function()
  eq(1, #M.parse_tags "#camelCase")
  eq(1, #M.parse_tags "#PascalCase")
  eq(1, #M.parse_tags "#snake_case")
  eq(1, #M.parse_tags "#kebab-case")
end

T["find_tags_in_string"]["should find nested tags"] = function()
  eq(1, #M.parse_tags " #inbox/processing")
  eq(1, #M.parse_tags " #inbox/to-read")
end

T["find_tags_in_string"]["should ignore escaped tags"] = function()
  local s = "I have a #meeting at noon \\#not-a-tag"
  eq({ { 10, 17, "Tag" } }, M.parse_tags(s))
  s = [[\#notatag]]
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore issue numbers"] = function()
  local s = "Issue: #100"
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore hexcolors"] = function()
  local s = "background: #f0f0f0"
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore anchor links that look like tags"] = function()
  local s = "[readme](README#installation)"
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore section in urls"] = function()
  local s = "https://example.com/page#section"
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore tags in HTML entities"] = function()
  eq({}, M.parse_tags "Here is an entity: &#NOT_A_TAG;")
end

T["find_tags_in_string"]["should ignore tags not on word boundaries"] = function()
  eq({}, M.parse_tags "foobar#notatag")
  eq({ { 9, 12, "Tag" } }, M.parse_tags "foo bar #tag")
end

T["find_tags_in_string"]["should ignore tags in markdown links with parentheses"] = function()
  local s = "[autobox](https://en.wikipedia.org/wiki/Object_type_(object-oriented_programming)#NOT_A_TAG)"
  eq({}, M.parse_tags(s))
end

T["find_tags_in_string"]["should ignore tags in html comments"] = function()
  local s = "<!-- #region -->"
  eq({}, M.parse_tags(s))
end

-- TODO: unicode tags
T["find_tags_in_string"]["should find non-English tags"] = function()
  eq(1, #M.parse_tags "#你好")
  eq(1, #M.parse_tags "#タグ")
  eq(1, #M.parse_tags "#mañana")
  eq(1, #M.parse_tags "#день")
  eq(1, #M.parse_tags "#项目_计划")
end

return T
