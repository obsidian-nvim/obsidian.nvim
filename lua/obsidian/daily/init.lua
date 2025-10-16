local periodic = require "obsidian.periodic"
local M = {}

-- Create daily period functions using the generalized periodic module
local daily_functions = periodic.create_period_functions(periodic.PERIODS.daily)

--- Get the path to a daily note.
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.daily_note_path = daily_functions.period_note_path

--- Open (or create) the daily note for today.
---
---@return obsidian.Note
M.today = daily_functions.this_period

--- Open (or create) the daily note from the last day.
---
---@return obsidian.Note
M.yesterday = daily_functions.last_period

--- Open (or create) the daily note for the next day.
---
---@return obsidian.Note
M.tomorrow = daily_functions.next_period

--- Open (or create) the daily note for today + `offset_days`.
---
---@return obsidian.Note
M.daily = daily_functions.period

return M
