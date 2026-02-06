---@param data obsidian.CommandArgs
return function(data)
  local new_name
  if string.len(new_name) > 0 then
    new_name = vim.trim(data.args)
  end
  require("obsidian.actions").rename(new_name)
end
