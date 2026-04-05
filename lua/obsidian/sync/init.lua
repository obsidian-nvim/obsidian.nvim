local client = require "obsidian.sync.client"
local manage = require "obsidian.sync.manage"
local log = require "obsidian.log"

local M = {}

M.setup = manage.setup
M.unlink = manage.unlink

---@param workspace? obsidian.Workspace
M.start = function(workspace)
  workspace = workspace or Obsidian.workspace
  client.start(tostring(workspace.root))
end

---@param workspace? obsidian.Workspace
M.stop = function(workspace)
  workspace = workspace or Obsidian.workspace
  client.stop(tostring(workspace.root))
end

---@param workspace? obsidian.Workspace
M.open_log = function(workspace)
  workspace = workspace or Obsidian.workspace
  client.open_log(tostring(workspace.root))
end

local actions = {
  {
    name = "start",
    text = "Start Sync",
    fn = M.start,
  },
  {
    name = "pause",
    text = "Pause Sync",
    fn = M.stop,
  },
  {
    name = "log",
    text = "View Sync Log",
    fn = M.open_log,
  },
  {
    name = "setup",
    text = "Setup Wizard",
    fn = M.setup,
  },
  {
    name = "unlink",
    text = "Unlink Vault From Remote",
    fn = M.unlink,
  },
}

M._actions = actions

---@param subcmd? string
function M.menu(subcmd)
  if not subcmd then
    vim.ui.select(actions, {
      prompt = "Obsidian Sync",
      format_item = function(item)
        return item.text
      end,
    }, function(choice)
      if not choice then
        return
      end
      choice.fn()
    end)
    return
  end

  local action = vim.iter(actions):find(function(act)
    return act.name == subcmd
  end)
  if not action then
    log.err("Unknown sync subcommand: " .. subcmd)
    return
  end
  action.fn()
end

---@param ws obsidian.Workspace
---@param vaults table<string, obsidian.sync.LocalVault>? -- pre-fetched vaults to avoid redundant shell-outs
---@return boolean
function M.is_configured(ws, vaults)
  vaults = vaults or client.list_local()
  if not vaults then
    return false
  end
  return vaults[tostring(ws.root)] ~= nil
end

return M
