---@param _ lsp.ReferenceParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(_, handler)
  ---@diagnostic disable-next-line: missing-fields
  require "obsidian.commands.follow_link" {}
end
