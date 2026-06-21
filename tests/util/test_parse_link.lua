local M = require "obsidian.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

-- TODO: test for all link types
local T = new_set()

T["should parse link"] = function()
  local location = M.parse_link "[[hi#^block]]"
  eq(location, "hi#^block")
end

T["header link"] = new_set()

T["header link"]["should find in wiki link"] = function()
  local location, name, t = M.parse_link "[[#Header]]"
  eq(location, "#Header")
  eq(name, "#Header")
  eq(t, "wiki")
end

T["header link"]["should find in wiki link with alias"] = function()
  local location, name, t = M.parse_link "[[#header|Header]]"
  eq(location, "#header")
  eq(name, "Header")
  eq(t, "wiki")
end

T["header link"]["should find in markdown link"] = function()
  local location, name, t = M.parse_link "[Header](#header)"
  eq(location, "#header")
  eq(name, "Header")
  eq(t, "markdown")
end

T["block link"] = new_set()

T["block link"]["should find in wiki link"] = function()
  local location, name, t = M.parse_link "[[#^block]]"
  eq(location, "#^block")
  eq(name, "#^block")
  eq(t, "wiki")
end

T["block link"]["should find in wiki link with alias"] = function()
  local location, name, t = M.parse_link "[[#^block|Block]]"
  eq(location, "#^block")
  eq(name, "Block")
  eq(t, "wiki")
end

T["block link"]["should find in markdown link"] = function()
  local location, name, t = M.parse_link "[Block](#^block)"
  eq(location, "#^block")
  eq(name, "Block")
  eq(t, "markdown")
end

return T
