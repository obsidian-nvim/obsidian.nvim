local log = require "obsidian.log"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  client.cache:index_vault()
end
