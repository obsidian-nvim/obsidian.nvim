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

  -- NOTE: seems the only sensible place to initialize client commands
  for k, f in pairs(require "obsidian.actions") do
    vim.lsp.commands["obsidian-ls." .. k] = function(params)
      f(unpack(params.arguments or {}))
    end
  end
  send_progress(dispatchers, "end", "Obsidian LSP server loaded.", 100)
end
