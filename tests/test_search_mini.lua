local M = require "obsidian.search"

local RefTypes = M.RefTypes

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_matches"] = function()
  local matches = M.find_matches(
    [[
- <https://youtube.com@Fireship>
- [Fireship](https://youtube.com@Fireship)
  ]],
    { RefTypes.NakedUrl }
  )
  eq(2, #matches)
end

T["find_tags"] = new_set()

T["find_tags"]["should find positions of all tags"] = function()
  local s = "I have a #meeting at noon"
  eq({ { 10, 17, RefTypes.Tag } }, M.find_tags(s))
end

T["find_tags"]["should ignore escaped tags"] = function()
  local s = "I have a #meeting at noon \\#not-a-tag"
  eq({ { 10, 17, RefTypes.Tag } }, M.find_tags(s))
  s = [[\#notatag]]
  eq({}, M.find_tags(s))
end

T["find_tags"]["should ignore anchor links that look like tags"] = function()
  local s = "[readme](README#installation)"
  eq({}, M.find_tags(s))
end

T["find_tags"]["should ignore section in urls"] = function()
  local s = "https://example.com/page#section"
  eq({}, M.find_tags(s))
end

T["find_tags"]["should ignore issue numbers"] = function()
  local s = "#100 is something"
  eq({}, M.find_tags(s))
end

T["find_tags"]["should ignore hexcolors"] = function()
  local s = "backgroud: #f0f0f0"
  eq({}, M.find_tags(s))
end

return T
