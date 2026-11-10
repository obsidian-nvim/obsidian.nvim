local Note = require "obsidian.note"

---@param _parsed obsidian.uri.Parsed
---@param path obsidian.Path|?
---@return obsidian.uri.Operation
return function(_parsed, path)
  if not path then
    return {}
  end
  if not path:is_file() then
    error(("Note not found: %s"):format(path), 0)
  end
  return { note = Note.from_file(path) }
end
