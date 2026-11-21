local commands = require "obsidian.lsp.commands"

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
    renameProvider = {
      prepareProvider = true,
    },
    referencesProvider = true,
    definitionProvider = true,
    documentSymbolProvider = true,
    documentLinkProvider = {
      resolveProvider = false,
    },
    inlayHintProvider = true,
    workspaceSymbolProvider = true,
    codeActionProvider = true,
    executeCommandProvider = {
      commands = commands.advertised(),
    },
    completionProvider = {
      resolveProvider = false,
      triggerCharacters = { "[", "#", "^" },
    },
    foldingRangeProvider = true,
    -- Needed so Neovim sends textDocument/didChange notifications, which
    -- triggers LspNotify and causes foldingRange to be re-requested on edits.
    textDocumentSync = {
      change = 1, -- Full
      save = true,
    },
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
            {
              scheme = "file",
              pattern = {
                glob = "**",
                matches = "folder",
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

---@param _       lsp.InitializeParams
---@param handler fun(_: any, res: lsp.InitializeResult)
return function(_, handler, dispatchers)
  send_progress(dispatchers, "begin", "Initializing obsidian LSP server...", 0)
  handler(nil, initializeResult)

  commands.install_client_commands()
  send_progress(dispatchers, "end", "Obsidian LSP server loaded.", 100)
end
