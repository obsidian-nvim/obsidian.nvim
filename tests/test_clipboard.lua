local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local M = require "obsidian.clipboard"

local T = new_set()

T["get_check_command for os"] = function()
  eq(M._get_list_command(), { "wl-paste", "--list-types" }) -- TODO: for x11
end

---NOTE: use neovim's clipboard capability to set the register to test if at least plain text is set
---TODO: run in child process
T["list contents of clipboard"] = function()
  vim.fn.setreg("+", "some plain text")
  local types = M.list_types()
  assert(types, "no nil")
  eq(true, vim.list_contains(types, "text/plain;charset=utf-8"))
  eq(true, vim.list_contains(types, "text/plain"))
end

T["get contents of clipboard"] = function()
  vim.fn.setreg("+", "some plain text")
  local types = M.get_content "text/plain"
  assert(types, "no nil")
  eq(types, { "some plain text" })
end

return T
