local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"

--- Get the path to a daily note.
---
---@param datetime integer|?
---@param config obsidian.config.ClientOpts
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
local daily_note_path = function(datetime, config)
  datetime = datetime and datetime or os.time()

  ---@type obsidian.Path
  local path = Path:new(require("obsidian").get_client().dir)

  if config.daily_notes.folder ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / config.daily_notes.folder
  elseif config.notes_subdir ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / config.notes_subdir
  end

  local id
  if config.daily_notes.date_format ~= nil then
    id = tostring(os.date(config.daily_notes.date_format, datetime))
  else
    id = tostring(os.date("%Y-%m-%d", datetime))
  end

  path = path / (id .. ".md")

  -- ID may contain additional path components, so make sure we use the stem.
  id = path.stem

  return path, id
end

--- Open (or create) the daily note.
---
---@param datetime integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@param config obsidian.config.ClientOpts
---
---@return obsidian.Note
---
---@private
local _daily = function(datetime, opts, config)
  opts = opts or {}

  local path, id = daily_note_path(datetime, config)

  ---@type string|?
  local alias
  if config.daily_notes.alias_format ~= nil then
    alias = tostring(os.date(config.daily_notes.alias_format, datetime))
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.new(id, {}, config.daily_notes.default_tags or {}, path)

    if alias then
      note:add_alias(alias)
      note.title = alias
    end

    if not opts.no_write then
      require("obsidian").get_client():write_note(note, { template = config.daily_notes.template })
    end
  end

  return note
end

--- Open (or create) the daily note for today.
---
---@param config obsidian.config.ClientOpts
---@return obsidian.Note
local today = function(config)
  return _daily(os.time(), {}, config)
end

--- Open (or create) the daily note from the last day.
---
---@param config obsidian.config.ClientOpts
---@return obsidian.Note
local yesterday = function(config)
  local now = os.time()
  local yesterday

  if config.daily_notes.workdays_only then
    yesterday = util.working_day_before(now)
  else
    yesterday = util.previous_day(now)
  end

  return _daily(yesterday, {}, config)
end

--- Open (or create) the daily note for the next day.
---
---@param config obsidian.config.ClientOpts
---@return obsidian.Note
local tomorrow = function(config)
  local now = os.time()
  local tomorrow

  if config.daily_notes.workdays_only then
    tomorrow = util.working_day_after(now)
  else
    tomorrow = util.next_day(now)
  end

  return _daily(tomorrow, {}, config)
end

--- Open (or create) the daily note for today + `offset_days`.
---
---@param offset_days integer|?
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@param config obsidian.config.ClientOpts
---
---@return obsidian.Note
local daily = function(offset_days, opts, config)
  return _daily(os.time() + (offset_days * 3600 * 24), opts, config)
end

return {
  daily_note_path = daily_note_path,
  daily = daily,
  tomorrow = tomorrow,
  yesterday = yesterday,
  today = today,
}
