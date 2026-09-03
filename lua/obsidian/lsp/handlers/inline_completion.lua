---@param params lsp.InlineCompletionParams
---@param callback fun(_: any, result: lsp.InlineCompletionItem[]|lsp.InlineCompletionList)
return function(params, callback)
  local bufnr = params and params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or 0

  require("obsidian.cache").when_ready(function()
    local note = require("obsidian.api").current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
    if not note then
      callback(nil, {})
      return
    end

    require("obsidian.resolvers").resolve("inline_completion", {
      bufnr = bufnr,
      note = note,
      position = params.position,
      context = params.context,
    }, function(items, err)
      callback(nil, err and {} or items or {})
    end)
  end)
end
