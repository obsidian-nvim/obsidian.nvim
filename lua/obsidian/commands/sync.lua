local sync = require "obsidian.sync"
local prompts = require "obsidian.editor.prompt"

---@param data obsidian.commands.Args
return function(data)
  local subcmd = data.args:len() > 0 and data.args or nil

  local has_configured = false
  for _, ws in ipairs(Obsidian.workspaces) do
    if sync.is_configured(ws) then
      has_configured = true
      break
    end
  end

  if not has_configured then
    local choice = prompts.confirm "No vaults are configured for syncing. Do you want to run the setup wizard?"
    if choice == "Yes" then
      sync.setup()
      return
    else
      return
    end
  end

  sync.menu(subcmd)
end
