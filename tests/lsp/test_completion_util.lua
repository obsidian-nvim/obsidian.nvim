local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local M = require "obsidian.lsp.handlers._completion"

local T, child = h.child_vault()

T["get_cmp_type"] = function()
  --                                          012345678
  --                                          |||||||||
  local t, prefix, ref_start = M.get_cmp_type("hello [[worl", 10)

  eq(t, 1) -- wiki
  eq(prefix, "worl")
  eq(ref_start, 6)

  --                                     1 2 3456
  --                                     | | ||||
  t, prefix, ref_start = M.get_cmp_type "你好 [[worl"

  eq(t, 1) -- wiki
  eq(prefix, "worl")
  eq(ref_start, 4)
end

return T
