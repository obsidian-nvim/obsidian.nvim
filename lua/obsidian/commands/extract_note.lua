local obsidian = require "obsidian"

---@param data obsidian.commands.Args
return function(data)
  obsidian.api.extract_note(data.args)
end
