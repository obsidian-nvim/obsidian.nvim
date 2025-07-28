local log = require "obsidian.log"
local search = require "obsidian.search"
local api = require "obsidian.api"

return function()
  local picker = Obsidian.picker
  if not picker then
    return log.err "No picker configured"
  end

  local note = api.current_note(0)
  assert(note, "not in a note")

  search.find_links(note, {}, function(entries)
    entries = vim.tbl_map(function(match)
      return match.link
    end, entries)

    -- Launch picker.
    picker:pick(entries, {
      prompt_title = "Links",
      callback = function(link)
        api.follow_link(link)
      end,
    })
  end)
end
