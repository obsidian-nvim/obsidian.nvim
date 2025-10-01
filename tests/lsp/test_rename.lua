local eq = MiniTest.expect.equality
local Path = require "obsidian.path"
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local target = [[---
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

local referencer = [==[

[[target]]
]==]

local function write(str, path)
  vim.fn.writefile(vim.split(str, "\n"), tostring(path))
end

T["rename current note"] = function()
  local root = Path.new(child.lua_get [[tostring(Obsidian.dir)]])
  local target_path = root / "target.md"
  write(target, target_path)

  child.lua(string.format([[vim.cmd("edit %s")]], target_path))
  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  local new_target_path = root / "new_target.md"
  eq(true, new_target_path:exists())
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq(target_expected, table.concat(lines, "\n"))
end

T["rename note under cursor"] = function()
  local root = Path.new(child.lua_get [[tostring(Obsidian.dir)]])
  local target_path = root / "target.md"
  local referencer_path = root / "referencer.md"
  write(target, target_path)
  write(referencer, referencer_path)

  child.lua(string.format([[vim.cmd("edit %s")]], referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  child.lua [[vim.cmd"wa"]]
  eq(true, (root / "new_target.md"):exists())
  local new_target_path = root / "new_target.md"
  local lines = vim.fn.readfile(tostring(new_target_path))

  eq(target_expected, table.concat(lines, "\n"))
end

local referencer2 = [==[

[[target#^block]]
]==]

local referencer2_expected = [==[
---
id: referencer
aliases: []
tags: []
---

[[new_target#^block]]
]==]

T["rename note without changing blocks and headers"] = function()
  local root = Path.new(child.lua_get [[tostring(Obsidian.dir)]])
  local target_path = root / "target.md"
  local referencer_path = root / "referencer.md"
  write(target, target_path)
  write(referencer2, referencer_path)

  child.lua(string.format([[vim.cmd("edit %s")]], referencer_path))
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  child.lua [[vim.cmd"wa"]]
  eq(true, (root / "new_target.md"):exists())
  local new_target_path = root / "new_target.md"
  local lines = vim.fn.readfile(tostring(new_target_path))

  local ref_lines = vim.fn.readfile(tostring(referencer_path))
  eq(referencer2_expected, table.concat(ref_lines, "\n"))

  eq(target_expected, table.concat(lines, "\n"))
end

return T
