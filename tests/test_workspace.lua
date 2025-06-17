local Path = require "obsidian.path"
local M = require "obsidian.workspace"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()

T["should be able to initialize a workspace"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local ws = M.new(tmpdir, { name = "test_workspace" })
  eq("test_workspace", ws.name)
  eq(true, tmpdir:resolve() == ws.path)
  eq(string.format("Workspace(name='test_workspace', path='%s', root='%s')", tmpdir, tmpdir), tostring(ws))
  tmpdir:rmdir()
end

T["should be able to initialize from cwd"] = function()
  local ws = M.new_from_cwd()
  local cwd = Path.cwd()
  eq(true, cwd == ws.path)
end

return T
