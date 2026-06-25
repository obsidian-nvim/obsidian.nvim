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

T["fs helpers"] = function()
  local dir = tostring(Obsidian.dir / "a" / "b")
  fs.mkdir(dir, { parents = true })
  eq(true, vim.uv.fs_stat(dir).type == "directory")

  local file = vim.fs.joinpath(dir, "note.md")
  vim.fn.writefile({ "content" }, file)
  eq(vim.fs.joinpath(dir, "note-1.md"), fs.unique_path(file))

  local copy = tostring(Obsidian.dir / "copy")
  fs.copy_dir(tostring(Obsidian.dir / "a"), copy)
  eq({ "content" }, vim.fn.readfile(vim.fs.joinpath(copy, "b", "note.md")))

  eq(true, fs.rm(tostring(Obsidian.dir / "a")))
  eq(nil, vim.uv.fs_stat(tostring(Obsidian.dir / "a")))
  eq(false, fs.rm(tostring(Obsidian.dir / "missing")))
end

return T
