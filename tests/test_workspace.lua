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

T["command"] = new_set()

T["command"]["lists workspaces registered after the docs workspace"] = function()
  local roots = {
    Path.temp { suffix = "-primary" },
    Path.temp { suffix = "-docs" },
    Path.temp { suffix = "-remote" },
  }
  for _, root in ipairs(roots) do
    root:mkdir()
  end

  local primary = assert(workspace.new { path = roots[1], name = "primary", strict = true })
  local docs = assert(workspace.new { path = roots[2], name = ".obsidian.wiki", strict = true })
  local remote = assert(workspace.new { path = roots[3], name = "github-issues", strict = true })

  local old_obsidian = Obsidian
  local picker = require "obsidian.picker"
  local old_select = picker.select
  local items, opts
  Obsidian = {
    workspace = primary,
    workspaces = { primary, docs, remote },
  }
  picker.select = function(values, select_opts)
    items, opts = values, select_opts
  end

  local ok, err = pcall(require "obsidian.commands.workspace", { args = "" })
  picker.select = old_select
  Obsidian = old_obsidian
  for _, root in ipairs(roots) do
    vim.fn.delete(tostring(root), "rf")
  end
  if not ok then
    error(err)
  end

  eq(2, #items)
  eq("primary", items[1].user_data.name)
  eq("github-issues", items[2].user_data.name)
  eq("[github-issues] @ '" .. tostring(roots[3]) .. "'", opts.format_item(items[2]))
end

return T
