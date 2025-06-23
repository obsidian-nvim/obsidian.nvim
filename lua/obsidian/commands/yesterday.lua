---@param client obsidian.Client
---@param _ CommandArgs
return function(client, _)
  local note = require("obsidian.daily").yesterday(client.opts)
  client:open_note(note)
end
