---@param client obsidian.Client
---@param _ CommandArgs
return function(client, _)
  local note = require("obsidian.daily").tomorrow()
  client:open_note(note)
end
