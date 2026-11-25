---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Operation
return function(parsed)
  require("obsidian.picker").grep_notes { query = parsed.query, dir = Obsidian.workspace.root }
  return { interactive = true }
end
