local Config = require "obsidian.lsp.config"

---@param client obsidian.Client
---@param params lsp.ExecuteCommandParams
return function(client, params)
  local cmd = params.command

  Config.actions[cmd].fn()

  -- return require("obsidian.lsp.handlers.commands." .. cmd)(client, params)
  -- return require "obsidian.lsp.handlers.commands.createNote"(client, params)
end
