local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["follow wiki links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[

[[target]]
]==],
    ["target.md"] = "",
  })
  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(files["target.md"], child.api.nvim_buf_get_name(0))
end

T["follow markdown links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[

[target](./target.md)
]==],
    ["target.md"] = "",
  })

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(files["target.md"], child.api.nvim_buf_get_name(0))
end

return T
