local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T = new_set()

T["completion"] = new_set()

T["completion"]["refs"] = new_set()

T["completion"]["refs"]["can_complete should handle wiki links with text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "simple text [[foo"
  local request = {
    context = {
      cursor_before_line = before,
      cursor_after_line = "",
      cursor = {
        character = vim.fn.strchars(before),
      },
    },
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(12, insert_start)
  eq(17, insert_end)
end

T["completion"]["refs"]["can_complete should handle wiki links with preceding Unicode text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "Unicode text ű [[foo"
  local request = {
    context = {
      cursor_before_line = before,
      cursor_after_line = "",
      cursor = {
        character = vim.fn.strchars(before),
      },
    },
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(15, insert_start)
  eq(20, insert_end)
end

return T
