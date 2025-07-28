local util = require "obsidian.util"
local api = require "obsidian.api"

return function()
  local note = assert(api.current_note(0, { collect_anchor_links = true }))

  ---@type obsidian.PickerEntry[]
  local picker_entries = {}
  for _, anchor in pairs(note.anchor_links) do
    local display = string.rep("#", anchor.level) .. " " .. anchor.header
    table.insert(
      picker_entries,
      { value = display, display = display, filename = tostring(note.path), lnum = anchor.line }
    )
  end

  -- De-duplicate and sort.
  picker_entries = util.tbl_unique(picker_entries)
  table.sort(picker_entries, function(a, b)
    return a.lnum < b.lnum
  end)

  local picker = assert(Obsidian.picker)
  picker:pick(picker_entries, { prompt_title = "Table of Contents" })
end
