local util = require "obsidian.lsp.util"

---@param client obsidian.Client
---@param params table
---@param handler function
return function(client, params, handler)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local symbols = util.get_headings(bufnr)
  handler(nil, symbols)
end
