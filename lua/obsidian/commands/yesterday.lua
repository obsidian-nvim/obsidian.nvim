---@param client obsidian.Client
---@param _ CommandArgs
return function(client, _)
  local note = client:yesterday()
  client:open_note(note)
end
