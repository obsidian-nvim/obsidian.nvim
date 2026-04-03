local diagnostics = require "obsidian.lsp.diagnostics.dispatcher"

---@param params lsp.DidOpenTextDocumentParams
---@param dispatchers table
return function(params, dispatchers)
  if not params or not params.textDocument or not params.textDocument.uri then
    return
  end

  diagnostics:cancel(params.textDocument.uri)
  diagnostics:run(dispatchers, params.textDocument.uri, params.textDocument.text)
end
