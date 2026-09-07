local ut = require "obsidian.uri.util"

--- Handle the `unique` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_unique(parsed)
  local note = require("obsidian.unique").new_unique_note()
  if not note then
    return ut.failure(parsed, "Unique note creation was cancelled")
  end

  ut.write_note(note, parsed, {
    content = ut.content(parsed),
    force_append = true,
  })
  note:open {
    sync = true,
    open_strategy = ut.pane_type_to_open_strategy(parsed.pane_type),
  }
  return ut.success(parsed, { note = note })
end

return handle_unique
