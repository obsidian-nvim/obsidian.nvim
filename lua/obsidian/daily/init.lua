local periodic = require "obsidian.periodic"

--- Daily notes module - uses the Periodic singleton
---@type Periodic
local daily = periodic.daily

local M = {}

--- Get the path to a daily note.
---
---@param datetime integer|?
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.daily_note_path = function(datetime)
  return daily:note_path(datetime)
end

--- Open (or create) the daily note for today.
---
---@return obsidian.Note
M.today = function()
  return daily:this()
end

--- Open (or create) the daily note from the last day.
---
---@return obsidian.Note
M.yesterday = function()
  return daily:last()
end

--- Open (or create) the daily note for the next day.
---
---@return obsidian.Note
M.tomorrow = function()
  return daily:next()
end

--- Open (or create) the daily note for today + `offset_days`.
---
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
M.daily = function(offset, opts)
  return daily:period(offset, opts)
end

---@param offset_start integer
---@param offset_end integer
---@param callback fun(note: obsidian.Note)
M.pick = function(offset_start, offset_end, callback)
  ---@type obsidian.PickerEntry[]
  local dailies = {}
  for offset = offset_end, offset_start, -1 do
    local datetime = os.time() + (offset * 3600 * 24)
    local daily_note_path = M.daily_note_path(datetime)
    local daily_note_alias = tostring(os.date(Obsidian.opts.daily_notes.alias_format or "%A %B %-d, %Y", datetime))
    if offset == 0 then
      daily_note_alias = daily_note_alias .. " @today"
    elseif offset == -1 then
      daily_note_alias = daily_note_alias .. " @yesterday"
    elseif offset == 1 then
      daily_note_alias = daily_note_alias .. " @tomorrow"
    end
    if not daily_note_path:is_file() then
      daily_note_alias = daily_note_alias .. " ➡️ create"
    end
    dailies[#dailies + 1] = {
      user_data = offset,
      text = daily_note_alias,
      filename = tostring(daily_note_path),
    }
  end

  Obsidian.picker.pick(dailies, {
    prompt_title = "Dailies",
    callback = function(entry)
      local note = M.daily(entry.user_data, {})
      callback(note)
    end,
  })
end

return M
