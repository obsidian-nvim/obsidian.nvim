local ut = require "obsidian.uri.util"

--- Handle the `hook-get-address` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_hook_get_address(parsed)
  local api = require "obsidian.api"
  local note = api.current_note(0)
  if not note or not note.path then
    return ut.failure(parsed, "No note found in the current buffer")
  end
  if parsed.vault and api.find_workspace(tostring(note.path)) ~= Obsidian.workspace then
    return ut.failure(parsed, "The current note is not in the selected workspace")
  end

  if not parsed.x_success then
    local display = note:display_name():gsub("]", "\\]")
    local markdown_link = ("[%s](%s)"):format(display, ut.note_uri(note))
    vim.fn.setreg("+", markdown_link)
  end

  return ut.success(parsed, { note = note })
end

return handle_hook_get_address
