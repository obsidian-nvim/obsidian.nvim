local periodic = require "obsidian.periodic"
local M = {}

-- Create weekly period functions using the generalized periodic module
local weekly_functions = periodic.create_period_functions(periodic.PERIODS.weekly)

--- Get the path to a weekly note.
---
---@param datetime integer|?
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.weekly_note_path = weekly_functions.period_note_path

--- Open (or create) the weekly note for the current week.
---
---@return obsidian.Note
M.this_week = weekly_functions.this_period

--- Open (or create) the weekly note for the last week.
---
---@return obsidian.Note
M.last_week = weekly_functions.last_period

--- Open (or create) the weekly note for the next week.
---
---@return obsidian.Note
M.next_week = weekly_functions.next_period

--- Open (or create) the weekly note for the current week + `offset_weeks`.
---
---@param offset_weeks integer|?
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
M.weekly = weekly_functions.period

return M
