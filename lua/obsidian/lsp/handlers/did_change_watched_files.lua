---@param params lsp.DidChangeWatchedFilesParams
return function(params)
  if not params or not params.changes then
    return
  end

  require("obsidian.lsp.watchfiles").handle(params.changes)
end
