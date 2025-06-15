local ms = vim.lsp.protocol.Methods

return setmetatable({
  [ms.initialize] = require "obsidian.lsp.handlers.initialize",
  [ms.initialized] = require "obsidian.lsp.handlers.initialized",
  [ms.textDocument_rename] = require "obsidian.lsp.handlers.rename",
}, {
  __index = function(_, k)
    -- vim.notify("obsidian_ls does not support method " .. k .. " yet", 3)
    return function() end
  end,
})
