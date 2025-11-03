---@param data obsidian.CommandArgs
return function(data)
  Obsidian.picker.grep_notes {
    query = data.args,
  }
end
