---@param data obsidian.CommandArgs
return function(data)
  local key = data.fargs[1]
  local value = #data.fargs > 1 and table.concat(data.fargs, " ", 2) or nil
  require("obsidian.actions").search_properties(key, value)
end
