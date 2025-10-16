local periodic = require "obsidian.periodic"
local M = {}

-- Create monthly period functions using the generalized periodic module
local monthly_functions = periodic.create_period_functions(periodic.PERIODS.monthly)

--- Get the path to a monthly note.
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.monthly_note_path = monthly_functions.period_note_path

--- Open (or create) the monthly note for the current month.
---
---@return obsidian.Note
M.this_month = monthly_functions.this_period

--- Open (or create) the monthly note for the last month.
---
---@return obsidian.Note
M.last_month = monthly_functions.last_period

--- Open (or create) the monthly note for the next month.
---
---@return obsidian.Note
M.next_month = monthly_functions.next_period

--- Open (or create) the monthly note for the current month + `offset_months`.
---
---@return obsidian.Note
M.monthly = monthly_functions.period

return M
