local log = require "obsidian.log"
local api = require "obsidian.api"

return function()
  local note = api.current_note(0)
  if not note then
    return log.info "not in a note"
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  local seen = {}
  for _, match in ipairs(note:links()) do
    if not seen[match.link] then
      entries[#entries + 1] = {
        text = match.link,
        user_data = match.link,
      }
      seen[match.link] = true
    end
  end

  Obsidian.picker.pick(entries, {
    prompt_title = "Links",
    callback = function(entry)
      api.follow_link(entry.user_data)
    end,
  })
end
