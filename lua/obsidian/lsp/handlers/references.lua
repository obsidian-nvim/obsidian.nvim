---@param _ lsp.ReferenceParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(_, handler)
  require "obsidian.lsp.handlers._references"(nil, {}, handler)
end
