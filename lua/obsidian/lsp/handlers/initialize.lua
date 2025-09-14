---@type lsp.InitializeResult
local initializeResult = {
  capabilities = {
    renameProvider = {
      prepareProvider = true,
    },
    referencesProvider = true,
    definitionProvider = true,
    colorProvider = true,
    textDocumentSync = 2,
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

---@param params lsp.InitializeParams
---@param handler function
return function(params, handler, _)
  return handler(nil, initializeResult)
end
