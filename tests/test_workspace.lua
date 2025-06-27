local Path = require "obsidian.path"
local workspace = require "obsidian.workspace"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["should be able to initialize a workspace"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local ws = workspace.new(tmpdir, { name = "test_workspace" })
  eq("test_workspace", ws.name)
  eq(true, tmpdir:resolve() == ws.path)
  tmpdir:rmdir()
end

return T
