local sync = require "obsidian.sync"
local api = require "obsidian.api"
local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  if not Obsidian.opts.sync.enabled then
    log.warn "Sync is disabled. Enable 'opts.sync.enabled = true' to use :Obsidian sync."
    return
  end

  local subcmd = data.args:len() > 0 and data.args or nil
  -- TODO: doc on how this command behaves

  -- TODO: or not logged in, or no vaults configured for syncing
  local has_configured = vim.iter(Obsidian.workspaces):any(sync.is_configured)

  if not has_configured then
    local choice = api.confirm "No vaults are configured for syncing. Do you want to run the setup wizard?"
    if choice == "Yes" then
      sync.wizard()
    else
      return
    end
  end

  sync.menu(subcmd)
end
