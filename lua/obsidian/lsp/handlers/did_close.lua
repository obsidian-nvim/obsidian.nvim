local diagnostics = require "obsidian.lsp.diagnostics.dispatcher"

---@param params lsp.DidCloseTextDocumentParams
---@param dispatchers table
return function(params, dispatchers)
  if not params or not params.textDocument or not params.textDocument.uri then
    return
  end

  diagnostics:clear(dispatchers, params.textDocument.uri)
end
