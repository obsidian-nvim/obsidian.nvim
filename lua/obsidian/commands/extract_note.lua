local obsidian = require "obsidian"

---@param data obsidian.CommandArgs
return function(data)
  obsidian.actions.extract_note(data.args)
end
