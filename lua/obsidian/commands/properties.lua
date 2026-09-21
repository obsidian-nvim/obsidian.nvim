---@param data obsidian.CommandArgs
return function(data)
  local key, value = data.fargs[1], data.fargs[2]
  require("obsidian.actions").search_properties(key, value)
end
