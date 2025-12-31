local periodic = require "obsidian.periodic"

--- Weekly notes module - uses the Periodic singleton
---@type Periodic
local weekly = periodic.weekly

local M = {}

--- Get the path to a weekly note.
---
---@param datetime integer|?
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.weekly_note_path = function(datetime)
  return weekly:note_path(datetime)
end

--- Open (or create) the weekly note for the current week.
---
---@return obsidian.Note
M.this_week = function()
  return weekly:this()
end

--- Open (or create) the weekly note for the last week.
---
---@return obsidian.Note
M.last_week = function()
  return weekly:last()
end

--- Open (or create) the weekly note for the next week.
---
---@return obsidian.Note
M.next_week = function()
  return weekly:next()
end

--- Open (or create) the weekly note for the current week + `offset_weeks`.
---
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
M.weekly = function(offset, opts)
  return weekly:period(offset, opts)
end

return M
