local periodic = require "obsidian.periodic"
local M = {}

-- Create quarterly period functions using the generalized periodic module
local quarterly_functions = periodic.create_period_functions(periodic.PERIODS.quarterly)

--- Get the path to a quarterly note.
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.quarterly_note_path = quarterly_functions.period_note_path

--- Open (or create) the quarterly note for the current quarter.
---
---@return obsidian.Note
M.this_quarter = quarterly_functions.this_period

--- Open (or create) the quarterly note for the last quarter.
---
---@return obsidian.Note
M.last_quarter = quarterly_functions.last_period

--- Open (or create) the quarterly note for the next quarter.
---
---@return obsidian.Note
M.next_quarter = quarterly_functions.next_period

--- Open (or create) the quarterly note for the current quarter + `offset_quarters`.
---
---@return obsidian.Note
M.quarterly = quarterly_functions.period

return M
