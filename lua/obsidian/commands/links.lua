local log = require "obsidian.log"
local api = require "obsidian.api"
local actions = require "obsidian.actions"
local picker = require "obsidian.picker"

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

  picker.select(entries, { prompt = "Links" }, function(items)
    local link = items[1]
    if link then
      actions.follow_link(link)
    end
  end)
end
