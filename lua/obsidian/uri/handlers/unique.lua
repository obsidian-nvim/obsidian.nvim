---@param _parsed obsidian.uri.Parsed
---@return obsidian.uri.Operation
return function(_parsed)
  local note = require("obsidian.unique").new_unique_note(nil, {
    source_path = Obsidian.workspace.root,
    write = false,
    create_dir = true,
    prompt_invalid_filename = false,
  })
  if not note then
    error("Unique note creation was cancelled", 0)
  end
  return { note = note }
end
