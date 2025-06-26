---@param client obsidian.Client
---@param params table
return function(client, params, handler, _)
  handler(nil, {
    placeholder = client:current_note().id,
  })

  -- TODO: check if cursor on link
  -- rename_current_note(client, params)
end
