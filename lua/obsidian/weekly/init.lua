local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"
local M = {}

--- Get the start of the week for a given datetime.
--- Week starts on Monday by default.
---
---@param datetime integer
---@param start_of_week integer|? Day of week (0=Sunday, 1=Monday, etc). Defaults to 1 (Monday).
---
---@return integer The datetime for the start of the week.
local function get_week_start(datetime, start_of_week)
  start_of_week = start_of_week or 1 -- Default to Monday

  -- Get the current day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
  local current_day = tonumber(os.date("%w", datetime))

  -- Calculate days to subtract to get to start of week
  local days_to_subtract = (current_day - start_of_week + 7) % 7

  -- Get the start of the week
  return datetime - (days_to_subtract * 24 * 60 * 60)
end

--- Get the path to a weekly note.
---
---@param datetime integer|?
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.weekly_note_path = function(datetime)
  datetime = datetime and datetime or os.time()

  ---@type obsidian.Path
  local path = Path.new(Obsidian.dir)

  local options = Obsidian.opts

  -- Get the start of the week for consistent week identification
  local week_start = get_week_start(datetime, options.weekly_notes.start_of_week)

  if options.weekly_notes.folder ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / options.weekly_notes.folder
  elseif options.notes_subdir ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / options.notes_subdir
  end

  local id
  if options.weekly_notes.date_format ~= nil then
    id = tostring(os.date(options.weekly_notes.date_format, week_start))
  else
    -- Default format: YYYY-Www (e.g., 2024-W42)
    id = tostring(os.date("%Y-W%V", week_start))
  end

  path = path / (id .. ".md")

  -- ID may contain additional path components, so make sure we use the stem.
  id = path.stem

  return path, id
end

--- Open (or create) the weekly note.
---
---@param datetime integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
---
local _weekly = function(datetime, opts)
  opts = opts or {}

  local path, id = M.weekly_note_path(datetime)

  local options = Obsidian.opts

  -- Get the start of the week for alias
  local week_start = get_week_start(datetime, options.weekly_notes.start_of_week)

  ---@type string|?
  local alias
  if options.weekly_notes.alias_format ~= nil then
    alias = tostring(os.date(options.weekly_notes.alias_format, week_start))
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.create {
      id = id,
      aliases = {},
      tags = options.weekly_notes.default_tags or {},
      dir = path:parent(),
    }

    if alias then
      note:add_alias(alias)
      note.title = alias
    end

    if not opts.no_write then
      note:write { template = options.weekly_notes.template }
    end
  end

  return note
end

--- Open (or create) the weekly note for the current week.
---
---@return obsidian.Note
M.this_week = function()
  return _weekly(os.time(), {})
end

--- Open (or create) the weekly note for the last week.
---
---@return obsidian.Note
M.last_week = function()
  local now = os.time()
  local last_week = now - (7 * 24 * 60 * 60)
  return _weekly(last_week, {})
end

--- Open (or create) the weekly note for the next week.
---
---@return obsidian.Note
M.next_week = function()
  local now = os.time()
  local next_week = now + (7 * 24 * 60 * 60)
  return _weekly(next_week, {})
end

--- Open (or create) the weekly note for the current week + `offset_weeks`.
---
---@param offset_weeks integer|?
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
M.weekly = function(offset_weeks, opts)
  return _weekly(os.time() + (offset_weeks * 7 * 24 * 60 * 60), opts)
end

return M
