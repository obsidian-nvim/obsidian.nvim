local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local Path = require "obsidian.path"

local T = new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init_with_setup.lua" }
      child.lua [[
Note = require"obsidian.note"
Obsidian.opts.disable_frontmatter = true
      ]]
    end,
    post_once = function()
      child.lua [[vim.fn.delete(tostring(Obsidian.dir), "rf")]]
      child.stop()
    end,
  },
}

local target = [[---
id: target
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
  local referencer_path = root / "referencer.md"
  write(target, target_path)
  write(referencer, referencer_path)

  child.lua(string.format([[vim.cmd("edit %s")]], target_path))
  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  local new_target_path = root / "new_target.md"
  eq(true, new_target_path:exists())
  local bufs = child.api.nvim_list_bufs()
  eq(3, #bufs)
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq("id: new_target", lines[2])
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

  eq("id: new_target", lines[2])
end

local referencer2 = [==[

[[target#^block]]
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
  eq([==[[[new_target#^block]]]==], ref_lines[2])

  eq("id: new_target", lines[2])
end

return T
