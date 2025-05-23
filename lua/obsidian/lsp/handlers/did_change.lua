local diagnostic = require "obsidian.lsp.diagnostic"

---@param client obsidian.Client
---@param params lsp.DidChangeTextDocumentParams
---@param handler function
return function(client, params, handler, _)
  diagnostic(client, params)
end
