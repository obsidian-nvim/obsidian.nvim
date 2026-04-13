---@param data obsidian.CommandArgs
return function(data)
  require("obsidian.picker").grep_notes {
    query = data.args,
  }
end
