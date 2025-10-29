local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["trigger with [["] = function()
  local referencer = [==[

[[tar
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.type_keys "A"

  local res = child.lsp.buf_request_sync(
    0,
    "textDocument/completion",
    child.lua_get "vim.lsp.util.make_position_params(0, 'utf-8')"
  )
  eq(1, #res)
  local response = res[1]
  local result = response.result

  eq(2, #result.items)
  eq("tar (create)", result.items[1].label)
  eq("target", result.items[2].label)
end

T["trigger with #"] = function()
  local referencer = [==[
---
tags:
  - this/is/a/tag
---

#thi
]==]

  local root = child.Obsidian.dir
  local referencer_path = root / "referencer.md"
  h.write(referencer, referencer_path)

  local target_path = root / "target.md"
  h.write("", target_path)

  child.cmd(string.format("edit %s", referencer_path))
  child.api.nvim_win_set_cursor(0, { 6, 0 })
  child.type_keys "A"

  local res = child.lsp.buf_request_sync(
    0,
    "textDocument/completion",
    child.lua_get "vim.lsp.util.make_position_params(0, 'utf-8')"
  )
  eq(1, #res)
  local response = res[1]
  local result = response.result

  eq(2, #result.items)
  eq("this/is/a/tag", result.items[1].label)
  eq("thi", result.items[2].label) -- NOTE: here because in test it is written to disk, in real case it will not duplicate
end

return T
