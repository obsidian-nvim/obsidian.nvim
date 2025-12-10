local obsidian = require "obsidian"

---@param data obsidian.CommandArgs
return function(data)
  obsidian.actions.link_new(data.args)
end
