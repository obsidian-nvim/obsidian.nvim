---@param data obsidian.CommandArgs
return function(data)
  local id = data.args:len() > 0 and data.args
  ---@diagnostic disable-next-line: param-type-mismatch
  require("obsidian.actions").new(id, function(note)
    note:open { sync = true }
  end)
end
