local client = require "obsidian.sync.client"
local manage = require "obsidian.sync.manage"
local log = require "obsidian.log"

local M = {}

M.setup = manage.setup
M.disconnect = manage.disconnect

---@param workspace? obsidian.Workspace
M.start = function(workspace)
  workspace = workspace or Obsidian.workspace
  client.start(tostring(workspace.root))
end

---@param workspace? obsidian.Workspace
M.pause = function(workspace)
  workspace = workspace or Obsidian.workspace
  local dir = tostring(workspace.root)
  local ok, err = client.pause(dir)

  if ok then
    log.info("Paused sync for %s", dir)
  else
    log.err("Failed to pause sync for %s: %s", dir, err)
  end
end

---@param workspace? obsidian.Workspace
M.log = function(workspace)
  workspace = workspace or Obsidian.workspace
  client.log(tostring(workspace.root))
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
    fn = M.pause,
  },
  {
    name = "log",
    text = "Open Sync Log",
    fn = M.log,
  },
  {
    name = "setup",
    text = "Setup Wizard",
    fn = M.setup,
  },
  {
    name = "disconnect",
    text = "Unlink Vault From Remote",
    fn = M.disconnect,
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
