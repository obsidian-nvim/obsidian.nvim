local Config = require "obsidian.lsp.config"

local completion_options

-- TODO: what about non-english chars, or emojis?
local chars = {}
for i = 32, 126 do
  table.insert(chars, string.char(i))
end

if Config.complete then
  completion_options = {
    triggerCharacters = chars,
    resolveProvider = true,
    completionItem = {
      labelDetailsSupport = true,
    },
  }
else
  completion_options = false
end

local initializeResult = {
  capabilities = {
    codeActionProvider = true,
    hoverProvider = true,
    definitionProvider = true,
    implementationProvider = true,
    declarationProvider = true,
    documentLinkProvider = true,
    -- TODO: Add diagnostic support
    diagnosticProvider = {
      interFileDependencies = false,
      workspaceDiagnostics = true,
    },
    typeDefinitionProvider = true,
    renameProvider = true,
    referencesProvider = true,
    documentSymbolProvider = true,
    executeCommandProvider = {
      commands = {
        "toggleCheckbox",
        "createNote",
      },
    },
    completionProvider = completion_options,
    textDocumentSync = {
      openClose = true,
      change = 1,
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
  vim.list_extend(initializeResult.capabilities.executeCommandProvider.commands, vim.tbl_keys(Config.actions))

  return handler(nil, initializeResult)
end
