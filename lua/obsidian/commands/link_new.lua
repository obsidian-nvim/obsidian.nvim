local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  api.link_new(data.args)
end
