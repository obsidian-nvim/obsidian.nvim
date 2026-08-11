---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local bufnr = params and params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or 0
  local range = params and params.range or nil

  require("obsidian.cache").when_ready(function()
    local note = require("obsidian.api").current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
    if not note then
      callback(nil, {})
      return
    end

    require("obsidian.resolvers").resolve("hints", {
      bufnr = bufnr,
      note = note,
      range = range,
    }, function(hints, err)
      callback(nil, err and {} or hints or {})
    end)
  end)
end
