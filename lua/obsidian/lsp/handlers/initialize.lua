---@type lsp.InitializeResult
local initializeResult = {
  capabilities = {
    renameProvider = {
      prepareProvider = true,
    },
    referencesProvider = true,
    definitionProvider = true,
    documentSymbolProvider = true,
    codeActionProvider = true,
    executeCommandProvider = {
      commands = vim.tbl_keys(require("obsidian.lsp.handlers._code_action").actions),
    },
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
