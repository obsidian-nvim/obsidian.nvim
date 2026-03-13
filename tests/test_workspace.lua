local Path = require "obsidian.path"
local workspace = require "obsidian.workspace"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local expect = MiniTest.expect

local T = new_set()

T["new"] = new_set()

T["new"]["should be able to initialize a workspace"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local ws = workspace.new {
    path = tmpdir,
    name = "test_workspace",
  }
  assert(ws, "workspace should be created")
  eq("test_workspace", ws.name)
  eq(true, tmpdir:resolve() == ws.path)
  eq(true, ws:is_resolved())
end

T["new"]["should create unresolved workspace for non-existent static path"] = function()
  local tmpdir = Path.temp()
  -- Do NOT create the directory
  local ws = workspace.new {
    path = tmpdir,
    name = "missing_workspace",
  }
  assert(ws, "workspace should still be created")
  eq("missing_workspace", ws.name)
  eq(false, ws:is_resolved())
  eq(nil, ws.path)
  eq(nil, ws.root)
  eq(nil, ws._resolve_path) -- static path, no function to retry
end

T["new"]["should create unresolved workspace for dynamic path returning nil"] = function()
  local ws = workspace.new {
    path = function()
      return nil
    end,
    name = "dynamic_nil",
  }
  assert(ws, "workspace should still be created")
  eq("dynamic_nil", ws.name)
  eq(false, ws:is_resolved())
  eq(nil, ws.path)
  eq(nil, ws.root)
  assert(ws._resolve_path, "should store the function for lazy re-evaluation")
end

T["new"]["should resolve dynamic path that returns valid path"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local ws = workspace.new {
    path = function()
      return tmpdir
    end,
    name = "dynamic_valid",
  }
  assert(ws, "workspace should be created")
  eq("dynamic_valid", ws.name)
  eq(true, ws:is_resolved())
  eq(true, tmpdir:resolve() == ws.path)
  assert(ws._resolve_path, "should still store the function for future re-evaluation")
end

T["resolve"] = new_set()

T["resolve"]["should resolve dynamic workspace when path becomes available"] = function()
  local tmpdir = Path.temp()
  -- Path does not exist yet
  local ws = workspace.new {
    path = function()
      if tmpdir:exists() then
        return tmpdir
      end
      return nil
    end,
    name = "deferred",
  }
  eq(false, ws:is_resolved())

  -- Now create the directory
  tmpdir:mkdir()
  eq(true, ws:resolve())
  eq(true, ws:is_resolved())
  eq(true, tmpdir:resolve() == ws.path)
end

T["resolve"]["should return true for already resolved workspace"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local ws = workspace.new {
    path = tmpdir,
    name = "already_resolved",
  }
  eq(true, ws:is_resolved())
  eq(true, ws:resolve())
end

T["resolve"]["should return false for static unresolved workspace"] = function()
  local tmpdir = Path.temp()
  local ws = workspace.new {
    path = tmpdir,
    name = "static_missing",
  }
  eq(false, ws:is_resolved())
  eq(false, ws:resolve()) -- no _resolve_path, so permanently unresolved
end

T["resolve"]["should update name from placeholder when resolved"] = function()
  local tmpdir = Path.temp()
  local ws = workspace.new {
    path = function()
      if tmpdir:exists() then
        return tmpdir
      end
      return nil
    end,
  }
  eq("(unnamed)", ws.name)
  eq(false, ws:is_resolved())

  tmpdir:mkdir()
  eq(true, ws:resolve())
  assert(ws.name ~= "(unnamed)", "name should be updated from path")
end

T["setup"] = new_set()

T["setup"]["should not error for no valid workspace"] = function()
  local tmpdir = Path.temp()
  -- All workspaces unresolved should NOT error anymore
  expect.no_error(function()
    workspace.setup {
      {
        path = tmpdir,
        name = "test_workspace that does not exist",
      },
    }
  end)
  -- But workspaces list should contain the unresolved workspace
  eq(1, #Obsidian.workspaces)
  eq(false, Obsidian.workspaces[1]:is_resolved())
  eq(nil, Obsidian.workspace) -- no active workspace
end

T["setup"]["should set workspace when at least one resolves"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()

  workspace.setup {
    {
      path = tmpdir,
      name = "test_workspace that does exist",
    },
  }

  assert(Obsidian.workspace, "should have an active workspace")
  eq("test_workspace that does exist", Obsidian.workspace.name)
end

T["setup"]["should include both resolved and unresolved workspaces"] = function()
  local tmpdir1 = Path.temp()
  tmpdir1:mkdir()
  local tmpdir2 = Path.temp()
  -- tmpdir2 does NOT exist

  workspace.setup {
    { path = tmpdir1, name = "valid" },
    { path = tmpdir2, name = "missing" },
  }

  eq(2, #Obsidian.workspaces)
  eq(true, Obsidian.workspaces[1]:is_resolved())
  eq(false, Obsidian.workspaces[2]:is_resolved())
  eq("valid", Obsidian.workspace.name)
end

T["find"] = new_set()

T["find"]["find and resolve workspace based on dirs"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local wss = workspace.setup {
    {
      path = tmpdir,
      name = "test_workspace",
    },
  }

  local subdir = tmpdir / "child"

  subdir:mkdir()

  eq(wss[1], workspace.find(subdir, wss))
end

T["find"]["should skip unresolved workspaces"] = function()
  local tmpdir1 = Path.temp()
  tmpdir1:mkdir()
  local tmpdir2 = Path.temp()
  -- tmpdir2 does NOT exist

  local wss = workspace.setup {
    { path = tmpdir1, name = "valid" },
    { path = tmpdir2, name = "missing" },
  }

  local subdir = tmpdir1 / "child"
  subdir:mkdir()

  -- Should find the resolved workspace, skip the unresolved one
  local found = workspace.find(subdir, wss)
  eq(wss[1], found)
  eq("valid", found.name)

  -- Should not find anything in a random directory
  local other = Path.temp()
  other:mkdir()
  eq(nil, workspace.find(other, wss))
end

T["detect"] = new_set()

T["detect"]["should detect vault from .obsidian/ folder"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()
  local subdir = tmpdir / "notes" / "daily"
  subdir:mkdir { parents = true }

  Obsidian.workspaces = {}

  local ws = workspace.detect(subdir)
  assert(ws, "should detect the vault")
  eq(true, ws:is_resolved())
  eq(tmpdir:resolve({ strict = true }), ws.root)
end

T["detect"]["should return nil when no .obsidian/ found"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  -- No .obsidian/ folder

  Obsidian.workspaces = {}

  local ws = workspace.detect(tmpdir)
  eq(nil, ws)
end

T["detect"]["should return existing workspace if vault already known"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()

  local wss = workspace.setup {
    { path = tmpdir, name = "my_vault" },
  }

  local ws = workspace.detect(tmpdir)
  assert(ws, "should return existing workspace")
  eq(wss[1], ws)
end

T["tostring"] = new_set()

T["tostring"]["should handle unresolved workspace"] = function()
  local ws = workspace.new {
    path = function()
      return nil
    end,
    name = "unresolved_ws",
  }
  local str = tostring(ws)
  assert(str:find("unresolved"), "should contain 'unresolved' in string representation")
  assert(str:find("unresolved_ws"), "should contain the workspace name")
end

T["tostring"]["should handle resolved workspace"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  workspace.setup {
    { path = tmpdir, name = "resolved_ws" },
  }
  local ws = Obsidian.workspaces[1]
  local str = tostring(ws)
  assert(str:find("resolved_ws"), "should contain the workspace name")
  assert(str:find(tostring(ws.path)), "should contain the path")
end

T["find_vault_root"] = new_set()

T["find_vault_root"]["should find vault root from subdirectory"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()
  local subdir = tmpdir / "notes" / "subfolder"
  subdir:mkdir { parents = true }

  local root = workspace.find_vault_root(subdir)
  assert(root, "should find vault root")
  eq(tmpdir, root)
end

T["find_vault_root"]["should return nil when no vault root found"] = function()
  local tmpdir = Path.temp()
  tmpdir:mkdir()
  -- No .obsidian/ folder
  local root = workspace.find_vault_root(tmpdir)
  eq(nil, root)
end

return T
