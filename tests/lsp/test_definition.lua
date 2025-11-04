local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local fs_eq = function(a, b)
  local normalize = vim.fs.normalize
  eq(normalize(a), normalize(b))
end

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

T["follow file url"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = ([==[

file://%s/test.lua
]==]):format(tostring(child.Obsidian.dir)),
    ["test.lua"] = "",
  })

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  fs_eq(files["test.lua"], child.api.nvim_buf_get_name(0))
end

-- TODO: expand to all filetypes
T["open attachment"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[

[target](./target.png)
]==],
  })

  -- TODO: Obsidian.opt.open.func
  child.lua [[
  Obsidian.opts.follow_img_func = function(uri)
    _G.uri = uri
  end
  Obsidian.opts.attachments.img_folder = "."
  ]]

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  fs_eq(tostring(child.Obsidian.dir / "target.png"), child.lua_get "uri")
end

return T
