local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local Path = require "obsidian.path"

local T = new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init_with_setup.lua" }
      child.lua [[
Note = require"obsidian.note"
client = require"obsidian".get_client()
      ]]
    end,
    post_once = function()
      child.lua [[vim.fn.delete(tostring(Obsidian.dir), "rf")]]
      child.stop()
    end,
  },
}

T["rename current note"] = function()
  child.lua [==[
target_path = tostring(Obsidian.dir / "target.md")
vim.fn.writefile({
  "---",
  "id: target",
  "---",
  "hello",
  "world",
}, target_path)

referencer_path = tostring(Obsidian.dir / "referencer.md")
vim.fn.writefile({
  "",
  "[[target]]",
}, referencer_path)

vim.cmd("edit " .. referencer_path)
]==]
  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  eq(true, (Path.new(root) / "new_target.md"):exists())
  local bufs = child.lua_get [[vim.api.nvim_list_bufs()]]
  eq(2, #bufs)

  child.lua_get [[vim.cmd.wa()]]
  -- local f1 = child.lua_get [[vim.api.nvim_buf_get_name(1)]]
  -- local f2 = child.lua_get [[vim.api.nvim_buf_get_name(2)]]
  -- print(f1, f2)
  --
  -- local lines = vim.fn.readfile(child.lua_get [[referencer_path]])
  -- eq("[[new_target]]", lines[2])
end

return T
