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
  assert(ws, "")
  eq("test_workspace", ws.name)
  eq(true, tmpdir:resolve() == ws.path)
end

T["new"]["should warn when workspace path does not exist"] = function()
  local tmpdir = Path.temp()
  local notifications = {}
  local notify = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(notifications, { msg = msg, level = level, opts = opts })
  end

  local ok, ws = pcall(workspace.new, {
    path = tmpdir,
    name = "missing_workspace",
  })
  vim.notify = notify

  if not ok then
    error(ws)
  end

  eq(nil, ws)
  eq(1, #notifications)
  eq("Skipping workspace 'missing_workspace': path does not exist: " .. tostring(tmpdir), notifications[1].msg)
  eq(vim.log.levels.WARN, notifications[1].level)
end

T["setup"] = new_set() -- TODO: test for cwd vs first ws

T["setup"]["should error for no valid workspace"] = function()
  local tmpdir = Path.temp()
  expect.error = function()
    workspace.setup {
      {
        path = tmpdir,
        name = "test_workspace that does not exist",
      },
    }
  end

  tmpdir:mkdir()

  expect.no_error = function()
    workspace.setup {
      {
        path = tmpdir,
        name = "test_workspace that does exist",
      },
    }
  end
end

T["set"] = new_set()

T["set"]["UI depends on its setting, not renderer availability"] = function()
  local root = Path.new(vim.fn.tempname())
  local vault = root / "vault"
  vault:mkdir { parents = true }
  local module_dir = root / "lua"
  module_dir:mkdir()
  vim.fn.writefile({ "error('renderer should not load')" }, tostring(module_dir / "markview.lua"))

  local original_rtp = vim.o.runtimepath
  local original_state = Obsidian
  local ui = require "obsidian.ui"
  local original_setup = ui.setup
  local calls = 0
  vim.opt.rtp:prepend(tostring(root))
  ui.setup = function()
    calls = calls + 1
  end

  local ok, err = pcall(function()
    Obsidian = {
      _opts = require("obsidian.config").normalize { legacy_commands = false },
      workspaces = {},
    }
    local ws = workspace.new { path = vault, name = "ui-test" }
    assert(ws, "test workspace missing")

    workspace.set(ws)
    eq(1, calls)

    ws.overrides = { ui = { enabled = false } }
    workspace.set(ws)
    eq(1, calls)

    ws.overrides = { ui = { enable = false } }
    workspace.set(ws)
    eq(1, calls)
  end)
  ui.setup = original_setup
  Obsidian = original_state
  vim.o.runtimepath = original_rtp
  vim.fn.delete(tostring(root), "rf")
  assert(ok, err)
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

return T
