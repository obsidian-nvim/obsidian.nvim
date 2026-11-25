local Note = require "obsidian.note"

---@param _parsed obsidian.uri.Parsed
---@param path obsidian.Path
---@return obsidian.uri.Operation
return function(_parsed, path)
  if path:is_file() then
    return { note = Note.from_file(path) }
  end
  return {
    note = Note.create {
      path = path,
      scope = "uri",
      template = Obsidian.opts.note.template,
      prompt_invalid_filename = false,
    },
  }
end
