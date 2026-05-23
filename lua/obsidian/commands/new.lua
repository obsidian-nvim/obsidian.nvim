---@param data obsidian.CommandArgs
return function(data)
  local id = data.args:len() > 0 and data.args or nil
  require("obsidian.actions").new(id, function(note)
    note:open { sync = true }
  end)
end
