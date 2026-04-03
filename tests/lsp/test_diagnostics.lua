local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

---@param cond_expr string
local function wait_for(cond_expr, timeout)
  timeout = timeout or 1500
  local ok = child.lua(
    string.format("return vim.wait(%d, function() return %s end)", timeout, cond_expr)
  )
  eq(true, ok)
end

T["publishes dead-link diagnostics on open"] = function()
  child.lua [[vim.g.diagnostic_interval = 10]]
  local root = child.Obsidian.dir
  local file_path = root / "file.md"
  h.write("[[missing]]", file_path)

  child.cmd(string.format("edit %s", file_path))

  wait_for("#vim.diagnostic.get(0) == 1")

  local diagnostics = child.lua_get "vim.diagnostic.get(0)"
  eq(1, #diagnostics)
  eq("dead-link", diagnostics[1].code)
  eq("Unresolved internal link", diagnostics[1].message)
end

T["does not publish diagnostics for valid links"] = function()
  child.lua [[vim.g.diagnostic_interval = 10]]
  local root = child.Obsidian.dir
  local target_path = root / "target.md"
  local file_path = root / "file.md"
  h.write("", target_path)
  h.write("[[target]]", file_path)

  child.cmd(string.format("edit %s", file_path))

  wait_for("#vim.diagnostic.get(0) == 0")

  local diagnostics = child.lua_get "vim.diagnostic.get(0)"
  eq(0, #diagnostics)
end

T["updates diagnostics on buffer change"] = function()
  child.lua [[vim.g.diagnostic_interval = 10]]
  local root = child.Obsidian.dir
  local target_path = root / "target.md"
  local file_path = root / "file.md"
  h.write("", target_path)
  h.write("[[missing]]", file_path)

  child.cmd(string.format("edit %s", file_path))

  wait_for("#vim.diagnostic.get(0) == 1")

  child.lua [=[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[target]]" })
  ]=]

  wait_for("#vim.diagnostic.get(0) == 0")

  local diagnostics = child.lua_get "vim.diagnostic.get(0)"
  eq(0, #diagnostics)
end

return T
