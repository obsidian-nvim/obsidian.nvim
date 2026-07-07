local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local fs = require "obsidian.fs"

local T = h.temp_vault

T["ignore gitignore"] = function()
  local gitignore = {
    "ignore/",
    "c.md",
  }
  local dir = Obsidian.dir

  -- TODO: helper.mock_vault_contents
  local ignore_dir = dir / "ignore"
  local a = tostring(dir / "a.md")
  local b = tostring(ignore_dir / "b.md")
  local c = tostring(dir / "c.md")
  local ignore_file = tostring(dir / ".gitignore")
  ignore_dir:mkdir()
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)
  vim.fn.writefile({}, c)
  vim.fn.writefile(gitignore, ignore_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end
  eq(#result, 1)
  eq(result[1], tostring(a))
end

T["ignore dot files"] = function()
  local dir = Obsidian.dir

  local a = tostring(dir / "a.md")
  local b = tostring(dir / ".b.md")
  vim.fn.writefile({}, a)
  vim.fn.writefile({}, b)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end
  eq(#result, 1)
  eq(result[1], tostring(a))
end

return T
