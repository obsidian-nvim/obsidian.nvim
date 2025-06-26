local ms = vim.lsp.protocol.Methods

return setmetatable({
  [ms.initialize] = require "obsidian.lsp.handlers.initialize",
  [ms.textDocument_rename] = require "obsidian.lsp.handlers.rename",
  [ms.initialized] = require "obsidian.lsp.handlers.initialized",
}, {
  __index = function(_, k)
    return function() end
  end,
})
