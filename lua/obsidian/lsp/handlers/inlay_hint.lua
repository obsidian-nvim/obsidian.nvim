---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local bufnr = params and params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or 0
  local range = params and params.range or nil

  require("obsidian.cache").when_ready(function()
    local ok, hints = pcall(require("obsidian.inlay_hints").collect, bufnr, range)
    if ok then
      callback(nil, hints)
    else
      require("obsidian.log").warn("failed to build inlay hints: %s", hints)
      callback(nil, {})
    end
  end)
end
