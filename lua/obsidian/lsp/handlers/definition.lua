local follow_link = require("obsidian.lsp.handlers._definition").follow_link
local api = require("obsidian").api

---@param _ lsp.DefinitionParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(_, handler)
  local link = api.cursor_link()

  if not link then
    return handler(nil, {})
  end
  follow_link(link, handler)
end
