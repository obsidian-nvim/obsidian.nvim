---@param data CommandArgs
return function(_, data)
  vim.lsp.buf.rename(vim.trim(data.args))
end
