local log = require "obsidian.log"
local actions = require "obsidian.actions"
local api = require "obsidian.api"

return function()
  local note = api.current_note(0)
  if not note then
    return log.info "not in a note"
  end

  local entries = vim.tbl_map(function(match)
    return match.link
  end, note:links())

  Obsidian.picker.select(entries, { prompt = "Links" }, function(items)
    local link = items[1]
    if link then
      api.follow_link(link)
    end
  end)
end
