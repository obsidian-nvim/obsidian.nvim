local chars = {}
for i = 32, 126 do
  table.insert(chars, string.char(i))
end

local completion_options = {
  triggerCharacters = chars,
  resolveProvider = true,
  completionItem = {
    labelDetailsSupport = true,
  },
}

---@type lsp.InitializeResult
local initializeResult = {
  capabilities = {
    renameProvider = {
      prepareProvider = true,
    },
    referencesProvider = true,
    definitionProvider = true,
    documentSymbolProvider = true,
    completionProvider = completion_options,
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

---@param _ lsp.InitializeParams
---@param handler fun(_: any, res: lsp.InitializeResult)
return function(_, handler, _)
  return handler(nil, initializeResult)
end
