local ms = vim.lsp.protocol.Methods

return setmetatable({
  [ms.initialize] = require "obsidian.lsp.handlers.initialize",
  [ms.textDocument_rename] = require "obsidian.lsp.handlers.rename",
  [ms.textDocument_prepareRename] = require "obsidian.lsp.handlers.prepare_rename",
  [ms.textDocument_references] = require "obsidian.lsp.handlers.references",
  [ms.textDocument_definition] = require "obsidian.lsp.handlers.definition",
  [ms.textDocument_documentSymbol] = require "obsidian.lsp.handlers.document_symbol",
}, {
  __index = function(_, _)
    return function() end
  end,
})
