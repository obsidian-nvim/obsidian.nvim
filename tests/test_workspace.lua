local Path = require "obsidian.path"
local workspace = require "obsidian.workspace"

describe("Workspace", function()
  it("should be able to initialize a workspace", function()
    local tmpdir = Path.temp()
    tmpdir:mkdir()
    local ws = workspace.new(tmpdir, { name = "test_workspace" })
    MiniTest.expect.equality("test_workspace", ws.name)
    MiniTest.expect.equality(true, tmpdir:resolve() == ws.path)
    tmpdir:rmdir()
  end)

  it("should be able to initialize from cwd", function()
    local ws = workspace.new_from_cwd()
    local cwd = Path.cwd()
    MiniTest.expect.equality(true, cwd == ws.path)
  end)
end)
