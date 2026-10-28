---@param data obsidian.commands.Args
return function(data)
  require("obsidian.actions").toggle_checkbox(data.line1, data.line2)
end
