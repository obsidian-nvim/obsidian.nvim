---@param data obsidian.CommandArgs
return function(data)
  Obsidian.picker.grep_notes {
    prompt_title = "Search",
    query = data.args,
  }
end
