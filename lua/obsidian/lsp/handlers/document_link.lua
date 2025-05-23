local util = require "obsidian.lsp.util"

---@param client obsidian.Client
---@param params lsp.DocumentLinkParams
---@param handler function
return function(client, params, handler, _)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local links = util.get_links(client, bufnr)
  handler(nil, links)
end
