local log = require "obsidian.log"
local api = require "obsidian.api"

return function()
  local picker = Obsidian.picker
  local note = api.current_note(0)
  if not note then
    return log.info "not in a note"
  end

  local entries = vim.tbl_map(function(match)
    return match.link
  end, note:links())

  picker.pick(entries, {
    prompt_title = "Links",
    callback = function(entry)
      api.follow_link(entry.user_data)
    end,
  })
end
