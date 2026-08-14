---@param params lsp.DidSaveTextDocumentParams
---@param dispatchers vim.lsp.rpc.Dispatchers?
return function(params, dispatchers)
  local uri = params and params.textDocument and params.textDocument.uri
  if not uri then
    return
  end

  local ok, path = pcall(vim.uri_to_fname, uri)
  if ok then
    require("obsidian.cache").notes.refresh(path)
  end

  if dispatchers then
    dispatchers.server_request "workspace/inlayHint/refresh"
  end
end
