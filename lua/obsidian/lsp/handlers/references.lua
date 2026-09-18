---@param params lsp.ReferenceParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(params, handler)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  require "obsidian.lsp.handlers._references"(nil, {
    tag = true,
    bufnr = bufnr,
    position = params.position,
    dir = require("obsidian.api").resolve_workspace_dir(vim.api.nvim_buf_get_name(bufnr)),
  }, handler)
end
