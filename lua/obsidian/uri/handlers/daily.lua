local ut = require "obsidian.uri.util"

--- Handle the `daily` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_daily(parsed)
  local note = require("obsidian.daily").today()
  ut.write_note(note, parsed, {
    content = ut.content(parsed),
    create_with_template = true,
  })

  if not parsed.silent then
    note:open {
      sync = true,
      open_strategy = ut.pane_type_to_open_strategy(parsed.pane_type),
    }
  end
  return ut.success(parsed, { note = note, silent = parsed.silent })
end

return handle_daily
