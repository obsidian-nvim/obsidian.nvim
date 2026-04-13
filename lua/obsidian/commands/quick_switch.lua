---@param data obsidian.CommandArgs
return function(data)
  require("obsidian.picker").find_notes {
    prompt_title = "Quick Switch",
    query = data.args,
  }
end
