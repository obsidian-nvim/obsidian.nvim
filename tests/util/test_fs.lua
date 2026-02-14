local M = require "obsidian.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["test"] = function()
  eq(M.relpath("/a", "/a/b"), "b")
  eq(M.relpath("/a/b/", "/a/d/e"), "../d/e")
  eq(M.relpath("/a/b/c", "/a"), "../..")
  eq(M.relpath("/a/b/c", "/a/d/e"), "../../d/e")
end

return T
