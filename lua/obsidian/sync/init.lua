local client = require "obsidian.sync.client"
local manage = require "obsidian.sync.manage"
local log = require "obsidian.log"

local M = {}

M.setup = manage.setup
M.disconnect = manage.disconnect

---@class obsidian.sync.ActionOpts
---@field silent boolean? -- if true, suppress informational messages (errors still shown)

---@param workspace? obsidian.Workspace
---@param opts obsidian.sync.ActionOpts?
M.start = function(workspace, opts)
  workspace = workspace or Obsidian.workspace
  opts = opts or {}
  client.start(tostring(workspace.root), { silent = opts.silent })
end

---@param workspace? obsidian.Workspace
---@param opts obsidian.sync.ActionOpts?
M.pause = function(workspace, opts)
  workspace = workspace or Obsidian.workspace
  opts = opts or {}
  local dir = tostring(workspace.root)
  local ok, err = client.pause(dir)

  if opts.silent then
    return
  end

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
