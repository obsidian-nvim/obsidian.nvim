---@type table<string, function>
local handlers = {
  ["initialize"] = require "obsidian.lsp.handlers.initialize",
  ["initialized"] = require "obsidian.lsp.handlers.initialized",
  ["workspace/didChangeWatchedFiles"] = require "obsidian.lsp.handlers.did_change_watched_files",
  ["workspace/didRenameFiles"] = require "obsidian.lsp.handlers.did_rename_files",
  ["workspace/symbol"] = require "obsidian.lsp.handlers.workspace_symbol",
  ["workspace/executeCommand"] = require "obsidian.lsp.handlers.workspace_execute_command",
  ["textDocument/rename"] = require "obsidian.lsp.handlers.rename",
  ["textDocument/prepareRename"] = require "obsidian.lsp.handlers.prepare_rename",
  ["textDocument/references"] = require "obsidian.lsp.handlers.references",
  ["textDocument/definition"] = require "obsidian.lsp.handlers.definition",
  ["textDocument/didSave"] = require "obsidian.lsp.handlers.did_save",
  ["textDocument/documentSymbol"] = require "obsidian.lsp.handlers.document_symbol",
  ["textDocument/codeAction"] = require "obsidian.lsp.handlers.code_action",
  ["textDocument/completion"] = require "obsidian.lsp.handlers.completion",
  ["textDocument/foldingRange"] = require "obsidian.lsp.handlers.folding_range",
  ["textDocument/inlayHint"] = require "obsidian.lsp.handlers.inlay_hint",
}

local base_lsp = require "obsidian.base.lsp"
local function route(base_handler, markdown_handler)
  return function(params, ...)
    if base_lsp.is_base_params(params) then
      return base_handler(params, ...)
    end
    return markdown_handler(params, ...)
  end
end

for method, base_handler in pairs(base_lsp.handlers) do
  local markdown_handler = handlers[method]
  if markdown_handler == nil then
    handlers[method] = base_handler
  else
    handlers[method] = route(base_handler, markdown_handler)
  end
end

return handlers
