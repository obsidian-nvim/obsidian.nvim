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
]==]

  child.lua [[vim.cmd("edit " .. referencer_path)]]
  child.lua [[vim.lsp.buf.rename("new_target", {})]]
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  eq(true, (Path.new(root) / "new_target.md"):exists())
  local bufs = child.api.nvim_list_bufs()
  eq(2, #bufs)
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq("id: new_target", lines[2])
end

return T
