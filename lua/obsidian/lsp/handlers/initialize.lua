local initializeResult = {
  capabilities = {
    renameProvider = {
      prepareProvider = true,
    },
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

---@param client obsidian.Client
---@param params lsp.InitializeParams
---@param handler function
return function(client, params, handler, _)
  return handler(nil, initializeResult)
end
