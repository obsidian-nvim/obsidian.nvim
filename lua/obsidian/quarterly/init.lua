local periodic = require "obsidian.periodic"

--- Quarterly notes module - uses the Periodic singleton
---@type Periodic
local quarterly = periodic.quarterly

local M = {}

--- Get the path to a quarterly note.
---
---@param datetime integer|?
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.quarterly_note_path = function(datetime)
  return quarterly:note_path(datetime)
end

--- Open (or create) the quarterly note for the current quarter.
---
---@return obsidian.Note
M.this_quarter = function()
  return quarterly:this()
end

--- Open (or create) the quarterly note for the last quarter.
---
---@return obsidian.Note
M.last_quarter = function()
  return quarterly:last()
end

--- Open (or create) the quarterly note for the next quarter.
---
---@return obsidian.Note
M.next_quarter = function()
  return quarterly:next()
end

--- Open (or create) the quarterly note for the current quarter + `offset_quarters`.
---
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
M.quarterly = function(offset, opts)
  return quarterly:period(offset, opts)
end

return M
