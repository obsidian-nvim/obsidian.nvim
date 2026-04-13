local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"
local M = {}

--- Get the path to a daily note.
---
---@param datetime integer|?
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.daily_note_path = function(datetime)
  datetime = datetime and datetime or os.time()

  ---@type obsidian.Path
  local path = Path.new(Obsidian.dir)

  local options = Obsidian.opts

  if options.daily_notes.folder ~= nil then
    path = path / options.daily_notes.folder
  elseif options.notes_subdir ~= nil then
    path = path / options.notes_subdir
  end

  local id = tostring(util.format_date(datetime, options.daily_notes.date_format))

  path = path / (id .. ".md")

  -- ID may contain additional path components, so make sure we use the stem.
  id = path.stem

  return path, id
end

--- Open (or create) the daily note.
---
---@param datetime integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
---
local _daily = function(datetime, opts)
  opts = opts or {}

  local path, id = M.daily_note_path(datetime)

  local options = Obsidian.opts

  ---@type string|?
  local alias
  if options.daily_notes.alias_format ~= nil then
    alias = tostring(util.format_date(datetime, options.daily_notes.alias_format))
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.create {
      id = id,
      verbatim = true,
      aliases = {},
      tags = options.daily_notes.default_tags or {},
      dir = path:parent(),
    }

    if alias then
      note:add_alias(alias)
    end

    if not opts.no_write then
      note:write { template = options.daily_notes.template }
    end
  end

  return note
end

--- Open (or create) the daily note for today.
---
---@return obsidian.Note
M.today = function()
  return _daily(os.time(), {})
end

--- Open (or create) the daily note from the last day.
---
---@return obsidian.Note
M.yesterday = function()
  local now = os.time()
  local yesterday

  if Obsidian.opts.daily_notes.workdays_only then
    yesterday = util.working_day_before(now)
  else
    yesterday = util.previous_day(now)
  end

  return _daily(yesterday, {})
end

--- Open (or create) the daily note for the next day.
---
---@return obsidian.Note
M.tomorrow = function()
  local now = os.time()
  local tomorrow

  if Obsidian.opts.daily_notes.workdays_only then
    tomorrow = util.working_day_after(now)
  else
    tomorrow = util.next_day(now)
  end

  return _daily(tomorrow, {})
end

---@class obsidian.daily.DailyOpts
---@field offset? integer Offset in days from today (e.g. -1 for yesterday,
---@field date? integer|? Specific date as a timestamp (overrides offset)
---@field no_write? boolean|? If true, the note will not be written to disk if it doesn't exist
---@field load? obsidian.note.LoadOpts|? Options to pass to Note.from_file when loading an existing note

--- Open (or create) the daily note for today + `offset_days`.
---
---@param opts obsidian.daily.DailyOpts|?
---
---@return obsidian.Note
M.daily = function(opts)
  opts = opts or {}
  local timestamp

  if opts.offset then
    assert(type(opts.offset) == "number", "offset must be a number")
    timestamp = os.time() + (opts.offset * 3600 * 24)
  else
    timestamp = opts.date or os.time()
  end

  return _daily(timestamp, opts)
end

---@param offset_start integer
---@param offset_end integer
---@param callback fun(note: obsidian.Note)
M.pick = function(offset_start, offset_end, callback)
  ---@type obsidian.PickerEntry[]
  local dailies = {}
  for offset = offset_end, offset_start, -1 do
    local datetime = os.time() + (offset * 3600 * 24)
    local daily_note_path = M.daily_note_path(datetime)
    local daily_note_alias =
      tostring(util.format_date(datetime, Obsidian.opts.daily_notes.alias_format or "%A %B %-d, %Y"))
    if offset == 0 then
      daily_note_alias = daily_note_alias .. " @today"
    elseif offset == -1 then
      daily_note_alias = daily_note_alias .. " @yesterday"
    elseif offset == 1 then
      daily_note_alias = daily_note_alias .. " @tomorrow"
    end
    if not daily_note_path:is_file() then
      daily_note_alias = daily_note_alias .. " ➡️ create"
    end
    dailies[#dailies + 1] = {
      user_data = offset,
      text = daily_note_alias,
      filename = tostring(daily_note_path),
    }
  end

  require("obsidian.picker").pick(dailies, {
    prompt_title = "Dailies",
    callback = function(entry)
      local note = M.daily {
        offset = entry.user_data,
      }
      callback(note)
    end,
  })
end

return M
