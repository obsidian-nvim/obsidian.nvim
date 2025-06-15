---@param client obsidian.Client
return function(client, params)
  local name = params.arguments[1]
  print("creating note " .. name)
  return client:create_note { title = name }
end
