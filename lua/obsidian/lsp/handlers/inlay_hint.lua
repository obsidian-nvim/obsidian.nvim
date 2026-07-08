local suggesters = {
  require "obsidian.lsp.inlay_hints.link",
}

---@param bufnr integer
---@param range lsp.Range|?
---@return lsp.InlayHint[]
local function get_hints(bufnr, range)
  ---@type lsp.InlayHint[]
  local hints = {}

  for _, suggest in ipairs(suggesters) do
    vim.list_extend(hints, suggest(bufnr, range))
  end

  return hints
end

---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local bufnr = params and params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or 0
  local range = params and params.range or nil

  require("obsidian.cache").when_ready(function()
    callback(nil, get_hints(bufnr, range))
  end)
end
