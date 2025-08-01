local cache = require "obsidian.cache"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  cache:rebuild_cache()
end
