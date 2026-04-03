---@type table<vim.lsp.protocol.Method, function>
return {
  ["initialize"] = require "obsidian.lsp.handlers.initialize",
  ["textDocument/didOpen"] = require "obsidian.lsp.handlers.did_open",
  ["textDocument/didChange"] = require "obsidian.lsp.handlers.did_change",
  ["textDocument/didSave"] = require "obsidian.lsp.handlers.did_save",
  ["textDocument/didClose"] = require "obsidian.lsp.handlers.did_close",
  ["workspace/didRenameFiles"] = require "obsidian.lsp.handlers.did_rename_files",
  ["textDocument/rename"] = require "obsidian.lsp.handlers.rename",
  ["textDocument/prepareRename"] = require "obsidian.lsp.handlers.prepare_rename",
  ["textDocument/references"] = require "obsidian.lsp.handlers.references",
  ["textDocument/definition"] = require "obsidian.lsp.handlers.definition",
  ["textDocument/documentSymbol"] = require "obsidian.lsp.handlers.document_symbol",
}
