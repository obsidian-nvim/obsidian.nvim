---@param params lsp.WorkspaceSymbolParams
---@param handler fun(_: any, result: lsp.WorkspaceSymbol[])
return function(params, handler)
  require "obsidian.lsp.handlers._workspace_symbol"(params.query, function(symbols)
    handler(nil, symbols)
  end)
end
