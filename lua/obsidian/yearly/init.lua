local periodic = require "obsidian.periodic"

--- Yearly notes module - uses the Periodic singleton
---@type Periodic
local yearly = periodic.yearly

local M = {}

--- Get the path to a yearly note.
---
---@param datetime integer|?
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.yearly_note_path = function(datetime)
  return yearly:note_path(datetime)
end

--- Open (or create) the yearly note for the current year.
---
---@return obsidian.Note
M.this_year = function()
  return yearly:this()
end

--- Open (or create) the yearly note for the last year.
---
---@return obsidian.Note
M.last_year = function()
  return yearly:last()
end

--- Open (or create) the yearly note for the next year.
---
---@return obsidian.Note
M.next_year = function()
  return yearly:next()
end

--- Open (or create) the yearly note for the current year + `offset_years`.
---
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
M.yearly = function(offset, opts)
  return yearly:period(offset, opts)
end

return M
