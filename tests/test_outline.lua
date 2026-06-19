local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[
    Outline = require "obsidian.outline"
    Obsidian.opts.outline.enabled = true
  ]],
}

T["get_continuation"] = new_set()

T["get_continuation"]["continues unordered list items"] = function()
  eq({ line = "  - " }, child.lua_get [[Outline._get_continuation("  - item")]])
end

T["get_continuation"]["continues ordered list items downward"] = function()
  eq({ line = "3) " }, child.lua_get [[Outline._get_continuation("2) item")]])
end

T["get_continuation"]["continues ordered list items upward with current number"] = function()
  eq({ line = "2. " }, child.lua_get [[Outline._get_continuation("2. item", { direction = "above" })]])
end

T["get_continuation"]["continues checkbox list items unchecked"] = function()
  eq({ line = "* [ ] " }, child.lua_get [[Outline._get_continuation("* [x] done")]])
  eq({ line = "2. [ ] " }, child.lua_get [[Outline._get_continuation("1. [!] done")]])
end

T["get_continuation"]["clears empty items downward"] = function()
  eq({ clear_current = "  " }, child.lua_get [[Outline._get_continuation("  - ")]])
  eq({ clear_current = "- " }, child.lua_get [[Outline._get_continuation("- [ ]   ")]])
  eq({ clear_current = "1. " }, child.lua_get [[Outline._get_continuation("1. [ ]")]])
end

T["get_continuation"]["requires insert cursor at end of line"] = function()
  eq(vim.NIL, child.lua_get [[Outline._get_continuation("- item", { col = 2 })]])
  eq({ line = "- " }, child.lua_get [[Outline._get_continuation("- item", { col = 7 })]])
end

T["continue"] = new_set()

T["continue"]["opens continuation below for normal o"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "- item" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[Outline.continue("below", "n")]]
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("- item", lines[1])
  eq("- ", lines[2])
end

T["continue"]["opens continuation above for normal O"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "2. item" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[Outline.continue("above", "n")]]
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("2. ", lines[1])
  eq("2. item", lines[2])
end

T["continue"]["clears empty checkbox below"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "- [x] " })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[Outline.continue("below", "n")]]
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("- ", lines[1])
  eq("", lines[2])
end

T["continue"]["falls back when disabled"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "- item" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[Obsidian.opts.outline.enabled = false; Outline.continue("below", "n"); Obsidian.opts.outline.enabled = true]]
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("- item", lines[1])
  eq("", lines[2])
end

return T
