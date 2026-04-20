---@param data obsidian.CommandArgs
return function(data)
  local new_name
  if string.len(new_name) > 0 then
    new_name = vim.trim(data.args)
  end
  vim.lsp.buf.rename(new_name)
end
