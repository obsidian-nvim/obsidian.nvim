local periodic = require "obsidian.periodic"
local M = {}

-- Create yearly period functions using the generalized periodic module
local yearly_functions = periodic.create_period_functions(periodic.PERIODS.yearly)

--- Get the path to a yearly note.
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.yearly_note_path = yearly_functions.period_note_path

--- Open (or create) the yearly note for the current year.
---
---@return obsidian.Note
M.this_year = yearly_functions.this_period

--- Open (or create) the yearly note for the last year.
---
---@return obsidian.Note
M.last_year = yearly_functions.last_period

--- Open (or create) the yearly note for the next year.
---
---@return obsidian.Note
M.next_year = yearly_functions.next_period

--- Open (or create) the yearly note for the current year + `offset_years`.
---
---@return obsidian.Note
M.yearly = yearly_functions.period

return M
