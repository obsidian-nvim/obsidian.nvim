local periodic = require "obsidian.periodic"

--- Monthly notes module - uses the Periodic singleton
---@type Periodic
local monthly = periodic.monthly

local M = {}

--- Get the path to a monthly note.
---
---@param datetime integer|?
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.monthly_note_path = function(datetime)
  return monthly:note_path(datetime)
end

--- Open (or create) the monthly note for the current month.
---
---@return obsidian.Note
M.this_month = function()
  return monthly:this()
end

--- Open (or create) the monthly note for the last month.
---
---@return obsidian.Note
M.last_month = function()
  return monthly:last()
end

--- Open (or create) the monthly note for the next month.
---
---@return obsidian.Note
M.next_month = function()
  return monthly:next()
end

--- Open (or create) the monthly note for the current month + `offset_months`.
---
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
M.monthly = function(offset, opts)
  return monthly:period(offset, opts)
end

return M
