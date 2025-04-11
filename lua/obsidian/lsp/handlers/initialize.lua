local config = require "obsidian.lsp.handlers.config"

local completion_options

if config.complete then
  completion_options = {
    triggerCharacters = { "[[" },
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
    hoverProvider = true,
    definitionProvider = true,
    implementationProvider = true,
    declarationProvider = true,
    signatureHelpProvider = {
      triggerCharacters = { "(", "," },
      retriggerCharacters = {},
    },
    -- Add diagnostic support
    diagnosticProvider = {
      interFileDependencies = false,
      workspaceDiagnostics = true,
    },
    typeDefinitionProvider = true,
    renameProvider = true,
    referencesProvider = true,
    documentSymbolProvider = true,
    completionProvider = completion_options,
    textDocumentSync = {
      openClose = true,
      change = 2,
    },
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

return function(_, params, handler, _)
  return handler(nil, initializeResult, params.context)
end
