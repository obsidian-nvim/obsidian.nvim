---@param data obsidian.CommandArgs
return function(data)
  Obsidian.picker:find_notes {
    prompt_title = "Quick Switch",
    query = data.args,
  }
end
