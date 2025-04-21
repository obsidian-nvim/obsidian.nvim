---@param client obsidian.Client
---@param _ CommandArgs
return function(client, _)
  local note = client:tomorrow()
  client:open_note(note)
end
