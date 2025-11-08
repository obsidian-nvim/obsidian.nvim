local obsidian = require "obsidian"

---@param data obsidian.CommandArgs
return function(data)
  obsidian.api.extract_note(data.args)
end
