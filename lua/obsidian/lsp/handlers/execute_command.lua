---@param client obsidian.Client
---@param params table
return function(client, params)
  -- return require "obsidian.lsp.handlers.commands.toggleCheckbox"(client, params)
  return require "obsidian.lsp.handlers.commands.createNote"(client, params)
end
