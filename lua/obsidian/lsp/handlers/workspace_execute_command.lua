local commands = require "obsidian.lsp.commands"

--- Fallback for LSP integrations that do not use vim.lsp.commands.
---@param params lsp.ExecuteCommandParams
---@param callback fun(err: lsp.ResponseError?, result: any)
return function(params, callback)
  callback(commands.execute(params), nil)
end
