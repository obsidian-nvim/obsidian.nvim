local obsidian = require "obsidian"

---@param data obsidian.CommandArgs
return function(data)
  obsidian.api.link_new(data.args)
end
