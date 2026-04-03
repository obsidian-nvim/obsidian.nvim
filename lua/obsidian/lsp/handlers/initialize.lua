local function send_progress(dispatchers, kind, title, percentage)
  dispatchers.notification("$/progress", {
    token = "obsidian-ls-progress",
    value = {
      kind = kind,
      title = title,
      percentage = percentage,
    },
  })
end

---@type lsp.InitializeResult
local initializeResult = {
  capabilities = {
    textDocumentSync = {
      openClose = true,
      change = vim.lsp.protocol.TextDocumentSyncKind.Full,
      save = {
        includeText = false,
      },
    },
    renameProvider = {
      prepareProvider = true,
    },
    referencesProvider = true,
    definitionProvider = true,
    documentSymbolProvider = true,
    workspace = {
      fileOperations = {
        didRename = {
          filters = {
            {
              scheme = "file",
              pattern = {
                glob = "**/*.md",
                matches = "file",
              },
            },
          },
        },
      },
    },
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

---@param _ lsp.InitializeParams
---@param handler fun(_: any, res: lsp.InitializeResult)
return function(_, handler, dispatchers)
  send_progress(dispatchers, "begin", "Initializing obsidian LSP server...", 0)
  handler(nil, initializeResult)
  send_progress(dispatchers, "end", "Obsidian LSP server loaded.", 100)
end
