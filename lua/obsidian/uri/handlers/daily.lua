---@param _parsed obsidian.uri.Parsed
---@return obsidian.uri.Operation
return function(_parsed)
  return { note = require("obsidian.daily").daily { dir = Obsidian.workspace.root } }
end
