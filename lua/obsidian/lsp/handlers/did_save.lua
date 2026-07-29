---@param params lsp.DidSaveTextDocumentParams
return function(params)
  local uri = params and params.textDocument and params.textDocument.uri
  if not uri then
    return
  end

  local ok, path = pcall(vim.uri_to_fname, uri)
  if ok then
    require("obsidian.cache").notes.refresh(path)
  end
end
