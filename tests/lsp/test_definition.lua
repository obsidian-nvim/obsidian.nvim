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
  fs_eq(files["target.md"], child.api.nvim_buf_get_name(0))
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
  fs_eq(files["target.md"], child.api.nvim_buf_get_name(0))
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

T["follow encoded headerlinks"] = function()
  local src = [==[
## This is a heading with spaces

[`some code`](#This%20is%20a%20heading%20with%20spaces)

[[#This is a heading with spaces|`some code`]]
]==]
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = src,
  })
  child.cmd("edit " .. files["test.md"])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(child.api.nvim_win_get_cursor(0), { 1, 0 })
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

local filetypes = require("obsidian.attachments").filetypes

local function test_ft(ext)
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = ([==[

[target](./target.%s)
]==]):format(ext),
  })

  child.lua [[
  Obsidian.opts.open.func = function(uri)
    _G.uri = uri
  end
  ]]

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  fs_eq(tostring(child.Obsidian.dir / "attachments" / ("target." .. ext)), child.lua_get "uri")
end

T["open attachment"] = function()
  for _, ft in ipairs(filetypes) do
    if ft ~= "md" then
      test_ft(ft)
    end
  end
end

return T
