local sync = require "obsidian.sync"
local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  local subcmd = data.args:len() > 0 and data.args or nil

  local has_configured = require "obsidian.iter"(Obsidian.workspaces):any(function(ws)
    return sync.is_configured(ws)
  end)

  if not has_configured then
    local choice = api.confirm "No vaults are configured for syncing. Do you want to run the setup wizard?"
    if choice == "Yes" then
      sync.setup()
      return
    else
      return
    end
  end

  sync.menu(subcmd)
end
