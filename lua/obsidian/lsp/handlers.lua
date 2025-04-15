local ms = vim.lsp.protocol.Methods

return setmetatable({
  [ms.initialize] = require "obsidian.lsp.handlers.initialize",
  [ms.textDocument_completion] = require "obsidian.lsp.handlers.completion",
  [ms.completionItem_resolve] = require "obsidian.lsp.handlers.completion_resolve",
  [ms.textDocument_hover] = require "obsidian.lsp.handlers.hover",
  [ms.workspace_diagnostic] = require "obsidian.lsp.handlers.workplace_diagnostics",
  [ms.textDocument_rename] = require "obsidian.lsp.handlers.rename",
  [ms.textDocument_references] = require "obsidian.lsp.handlers.references",
  [ms.textDocument_documentSymbol] = require "obsidian.lsp.handlers.document_symbol",
  [ms.textDocument_documentLink] = require "obsidian.lsp.handlers.document_link",
}, {
  __index = function(_, k)
    print("obsidian_ls does not support method " .. k .. " yet")
    return function() end
  end,
})
