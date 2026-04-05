local sync = require "obsidian.sync"
local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  local subcmd = data.args:len() > 0 and data.args or nil
  -- TODO: doc on how this command behaves

  -- TODO: or not logged in, or no vaults configured for syncing
  local has_configured = vim.iter(Obsidian.workspaces):any(sync.is_configured)

  if not has_configured then
    local choice = api.confirm "No vaults are configured for syncing. Do you want to run the setup wizard?"
    if choice == "Yes" then
      require("obsidian.setup").wizard()
    else
      return
    end
  end

  require("obsidian.sync").menu(subcmd)
end
