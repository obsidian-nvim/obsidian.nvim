local log = require "obsidian.log"
local api = require "obsidian.api"
local navigation = require "obsidian.navigation"
local picker = require "obsidian.picker"

return function()
  local note = api.current_note(0)
  if not note then
    return log.info "not in a note"
  end

  local entries = vim.tbl_map(function(match)
    return match.link
  end, note:links())

  picker.select(entries, { prompt = "Links" }, function(items)
    local link = items and items[1]
    if link then
      navigation.follow_link(link)
    end
  end)
end
