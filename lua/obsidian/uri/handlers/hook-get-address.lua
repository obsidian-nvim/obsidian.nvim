local api = require "obsidian.api"

---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Operation
return function(parsed)
  local note = api.current_note(0)
  if not note or not note.path then
    error("No note found in the current buffer", 0)
  end
  if parsed.vault and api.find_workspace(tostring(note.path)) ~= Obsidian.workspace then
    error("The current note is not in the selected workspace", 0)
  end
  if not parsed.x_success then
    local display = note:display_name():gsub("]", "\\]")
    local url = require("obsidian.uri").for_note(note)
    vim.fn.setreg("+", ("[%s](%s)"):format(display, url))
  end
  return { note = note }
end
