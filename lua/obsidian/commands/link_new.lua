local obsidian = require "obsidian"

---@param data obsidian.CommandArgs
return function(data)
  obsidian.actions.link_new(data.args, obsidian.api.get_visual_selection())
end
