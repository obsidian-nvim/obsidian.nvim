---@param data obsidian.CommandArgs
return function(data)
  local id = data.args:len() > 0 and data.args
  require("obsidian.actions").new(id)
end
