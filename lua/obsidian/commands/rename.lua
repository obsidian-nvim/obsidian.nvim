---@param data CommandArgs
return function(_, data)
  local new_name = vim.trim(data.args)
  if #new_name == 0 then
    vim.lsp.buf.rename()
  else
    vim.lsp.buf.rename(new_name)
  end
end
