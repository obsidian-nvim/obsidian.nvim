local initializeResult = {
  capabilities = {
    renameProvider = true,
  },
  serverInfo = {
    name = "obsidian-ls",
    version = "1.0.0",
  },
}

---@param params table
---@param handler function
return function(_, params, handler, _)
  return handler(nil, initializeResult, params.context)
end
