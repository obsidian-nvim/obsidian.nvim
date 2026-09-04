---@param params lsp.DocumentLinkParams
return function(params, handler)
  local path = require("obsidian.link").includeexpr(vim.uri_to_fname(params.textDocument.uri))
  print(path)
  handler()
end
