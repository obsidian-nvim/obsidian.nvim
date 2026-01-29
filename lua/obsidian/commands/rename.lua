---@param data obsidian.CommandArgs
return function(data)
  local new_name = vim.trim(data.args)
  if string.len(new_name) then
    require("obsidian.actions").rename(new_name)
  end
end
