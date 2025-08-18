local ms = vim.lsp.protocol.Methods

return setmetatable({
  [ms.initialize] = require "obsidian.lsp.handlers.initialize",
  [ms.textDocument_rename] = require "obsidian.lsp.handlers.rename",
  [ms.textDocument_prepareRename] = require "obsidian.lsp.handlers.prepare_rename",
  [ms.initialized] = require "obsidian.lsp.handlers.initialized",
  [ms.textDocument_references] = require "obsidian.lsp.handlers.references",
  [ms.textDocument_definition] = require "obsidian.lsp.handlers.definition",
}, {
  __index = function(_, k)
    return function() end
  end,
})
