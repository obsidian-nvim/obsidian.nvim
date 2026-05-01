---@param data obsidian.CommandArgs
return function(data)
  local new_name
  if data.args and string.len(data.args) > 0 then
    new_name = vim.trim(data.args)
  end
  vim.lsp.buf.rename(new_name)
end
