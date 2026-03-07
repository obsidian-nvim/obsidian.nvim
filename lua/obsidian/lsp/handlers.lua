---@type table<vim.lsp.protocol.Method, function>
return {
  ["initialize"] = require "obsidian.lsp.handlers.initialize",
  ["textDocument/rename"] = require "obsidian.lsp.handlers.rename",
  ["textDocument/prepareRename"] = require "obsidian.lsp.handlers.prepare_rename",
  ["textDocument/references"] = require "obsidian.lsp.handlers.references",
  ["textDocument/definition"] = require "obsidian.lsp.handlers.definition",
  ["textDocument/documentSymbol"] = require "obsidian.lsp.handlers.document_symbol",
}
