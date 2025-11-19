local M = require "obsidian.yaml.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["comments"] = new_set()

T["comments"]["should strip comments from a string"] = function()
  eq("foo: 1", M.strip_comments "foo: 1  # this is a comment")
end

T["comments"]["should strip comments even when they start at the beginning of the string"] = function()
  eq("", M.strip_comments "# foo: 1")
end

T["comments"]["should ignore '#' when enclosed in quotes"] = function()
  eq([["hashtags start with '#'"]], M.strip_comments [["hashtags start with '#'"]])
end

T["comments"]["should ignore an escaped '#'"] = function()
  eq([[hashtags start with \# right?]], M.strip_comments [[hashtags start with \# right?]])
end

return T
