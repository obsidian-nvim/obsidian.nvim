local Path = require "obsidian.path"
local Note = require "obsidian.note"
local M = {}

--- Get the start of the month for a given datetime.
---
---@param datetime integer
---
---@return integer The datetime for the start of the month.
local function get_month_start(datetime)
  -- Get year, month, and day
  local year = tonumber(os.date("%Y", datetime))
  local month = tonumber(os.date("%m", datetime))

  -- Return timestamp for the 1st day of the month at midnight
  return os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
end

--- Get the path to a monthly note.
---
---@param datetime integer|?
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.monthly_note_path = function(datetime)
  datetime = datetime and datetime or os.time()

  ---@type obsidian.Path
  local path = Path.new(Obsidian.dir)

  local options = Obsidian.opts

  -- Get the start of the month for consistent month identification
  local month_start = get_month_start(datetime)

  if options.monthly_notes.folder ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / options.monthly_notes.folder
  elseif options.notes_subdir ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / options.notes_subdir
  end

  local id
  if options.monthly_notes.date_format ~= nil then
    id = tostring(os.date(options.monthly_notes.date_format, month_start))
  else
    -- Default format: YYYY-MM (e.g., 2024-10)
    id = tostring(os.date("%Y-%m", month_start))
  end

  path = path / (id .. ".md")

  -- ID may contain additional path components, so make sure we use the stem.
  id = path.stem

  return path, id
end

--- Open (or create) the monthly note.
---
---@param datetime integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
---
local _monthly = function(datetime, opts)
  opts = opts or {}

  local path, id = M.monthly_note_path(datetime)

  local options = Obsidian.opts

  -- Get the start of the month for alias
  local month_start = get_month_start(datetime)

  ---@type string|?
  local alias
  if options.monthly_notes.alias_format ~= nil then
    alias = tostring(os.date(options.monthly_notes.alias_format, month_start))
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.create {
      id = id,
      aliases = {},
      tags = options.monthly_notes.default_tags or {},
      dir = path:parent(),
    }

    if alias then
      note:add_alias(alias)
      note.title = alias
    end

    if not opts.no_write then
      note:write { template = options.monthly_notes.template }
    end
  end

  return note
end

--- Open (or create) the monthly note for the current month.
---
---@return obsidian.Note
M.this_month = function()
  return _monthly(os.time(), {})
end

--- Open (or create) the monthly note for the last month.
---
---@return obsidian.Note
M.last_month = function()
  local now = os.time()
  local year = tonumber(os.date("%Y", now))
  local month = tonumber(os.date("%m", now))

  -- Go back one month
  month = month - 1
  if month == 0 then
    month = 12
    year = year - 1
  end

  local last_month = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
  return _monthly(last_month, {})
end

--- Open (or create) the monthly note for the next month.
---
---@return obsidian.Note
M.next_month = function()
  local now = os.time()
  local year = tonumber(os.date("%Y", now))
  local month = tonumber(os.date("%m", now))

  -- Go forward one month
  month = month + 1
  if month == 13 then
    month = 1
    year = year + 1
  end

  local next_month = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
  return _monthly(next_month, {})
end

--- Open (or create) the monthly note for the current month + `offset_months`.
---
---@param offset_months integer|?
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
M.monthly = function(offset_months, opts)
  local now = os.time()
  local year = tonumber(os.date("%Y", now))
  local month = tonumber(os.date("%m", now))

  -- Calculate new month and year
  month = month + offset_months

  -- Handle month overflow/underflow
  while month > 12 do
    month = month - 12
    year = year + 1
  end

  while month < 1 do
    month = month + 12
    year = year - 1
  end

  local target_month = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
  return _monthly(target_month, opts)
end

return M
