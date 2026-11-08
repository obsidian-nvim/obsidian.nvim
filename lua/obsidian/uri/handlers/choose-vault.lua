---@param _parsed obsidian.uri.Parsed
---@return obsidian.uri.Operation
return function(_parsed)
  require("obsidian.workspace").pick()
  return { interactive = true }
end
