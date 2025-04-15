-- TODO: move to the idea of textEdits

---@param obsidian_client obsidian.Client
---@param params table
---@param handler function
return function(obsidian_client, params, handler, _)
  require "obsidian.commands.rename"(obsidian_client, { args = params.newName })
end
