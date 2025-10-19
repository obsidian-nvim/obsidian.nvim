local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local target = "target.md"
local ref = "ref.md"

local target_content = [[---
id: target
aliases: []
tags: []
---
hello
world]]

local target_expected = [[---
id: new_target
aliases: []
tags: []
---
hello
world]]

local ref_content = [==[

[[target]]
]==]

T["rename current note"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
  })

  local new_target_path = root / "new_target.md"

  child.cmd("edit " .. files[target])
  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  eq(true, new_target_path:exists())
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq(target_expected, table.concat(lines, "\n"))
end

T["rename note under cursor"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    [ref] = ref_content,
  })
  local new_target_path = (root / "new_target.md")

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  child.cmd "wa"
  eq(true, new_target_path:exists())
  local lines = vim.fn.readfile(tostring(new_target_path))

  eq(target_expected, table.concat(lines, "\n"))
end

local referencer2_expected = [==[
---
id: ref
aliases: []
tags: []
---

[[new_target#^block]]
]==]

T["rename note without changing blocks and headers"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    [ref] = [==[

[[target#^block]]
]==],
  })
  local new_target_path = root / "new_target.md"

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  child.cmd "wa"
  eq(true, new_target_path:exists())

  local lines = h.read(new_target_path)
  local ref_lines = h.read(files[ref])
  eq(referencer2_expected, table.concat(ref_lines, "\n"))
  eq(target_expected, table.concat(lines, "\n"))
end

return T
