local log = require "obsidian.log"
local api = require "obsidian.api"

return function()
  local picker = Obsidian.picker
  if not picker then
    return log.err "No picker configured"
  end

  local note = api.current_note(0)
  assert(note, "not in a note")

  local entries = vim.tbl_map(function(match)
    return match.link
  end, note:links {})

  -- Launch picker.
  picker:pick(entries, {
    prompt_title = "Links",
    callback = function(entry)
      api.follow_link(entry.value)
    end,
  })
end
