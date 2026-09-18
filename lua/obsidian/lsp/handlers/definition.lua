local api = require("obsidian").api

---@param params lsp.DefinitionParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(params, handler)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local link, _, range = api.cursor_link(bufnr, params.position)

  if not link then
    return handler(nil, {})
  end
  require("obsidian.lsp.handlers._definition").follow_link(link, handler, {
    range = range,
    bufnr = bufnr,
    cursor_row = params.position.line + 1,
  })
end
