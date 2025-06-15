---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  client.cache:rebuild_cache()
end
