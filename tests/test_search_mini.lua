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

return T
