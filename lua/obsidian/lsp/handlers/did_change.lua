local refresh_pending = false

---@param params lsp.DidChangeTextDocumentParams
---@param dispatchers table
return function(params, dispatchers)
  if params and params.textDocument and params.textDocument.uri then
    require("obsidian.inlay_hints").clear(vim.uri_to_bufnr(params.textDocument.uri))
  end

  if refresh_pending or not dispatchers or not dispatchers.server_request then
    return
  end

  refresh_pending = true
  vim.defer_fn(function()
    refresh_pending = false

    -- Ask the client to re-request inlay hints after buffer edits. Neovim exposes
    -- this through the LSP refresh request, not a public Lua refresh function.
    dispatchers.server_request("workspace/inlayHint/refresh", nil)
  end, 100)
end
