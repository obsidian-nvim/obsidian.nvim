local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"

--- Get the path to a daily note.
---
---@param datetime integer|?
---@param opts obsidian.config.ClientOpts
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
local daily_note_path = function(datetime, opts)
  datetime = datetime and datetime or os.time()
  local client = require("obsidian").get_client()
  opts = opts or client.opts
  ---@type obsidian.Path
  local path = Path:new(client.dir)

  if opts.daily_notes.folder ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / opts.daily_notes.folder
  elseif opts.notes_subdir ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / opts.notes_subdir
  end

  local id
  if opts.daily_notes.date_format ~= nil then
    id = tostring(os.date(opts.daily_notes.date_format, datetime))
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
---
---@return obsidian.Note
---
---@private
local _daily = function(datetime, opts)
  opts = opts or {}

  local client = require("obsidian").get_client()
  local path, id = daily_note_path(datetime, opts)

  ---@type string|?
  local alias
  if client.opts.daily_notes.alias_format ~= nil then
    alias = tostring(os.date(client.opts.daily_notes.alias_format, datetime))
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.new(id, {}, client.opts.daily_notes.default_tags or {}, path)

    if alias then
      note:add_alias(alias)
      note.title = alias
    end

    if not opts.no_write then
      client:write_note(note, { template = client.opts.daily_notes.template })
    end
  end

  return note
end

--- Open (or create) the daily note for today.
---
---@return obsidian.Note
local today = function(opts)
  local client = require("obsidian").get_client()
  opts = opts or client.opts
  return _daily(os.time(), opts)
end

--- Open (or create) the daily note from the last day.
---
---@return obsidian.Note
local yesterday = function(opts)
  local now = os.time()
  local yesterday

  if opts.daily_notes.workdays_only then
    yesterday = util.working_day_before(now)
  else
    yesterday = util.previous_day(now)
  end

  return _daily(yesterday, opts)
end

--- Open (or create) the daily note for the next day.
---
---@return obsidian.Note
local tomorrow = function(opts)
  local now = os.time()
  local tomorrow
  local client = require("obsidian").get_client()
  opts = opts or client.opts

  if opts.daily_notes.workdays_only then
    tomorrow = util.working_day_after(now)
  else
    tomorrow = util.next_day(now)
  end

  return _daily(tomorrow, opts)
end

--- Open (or create) the daily note for today + `offset_days`.
---
---@param offset_days integer|?
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
local daily = function(offset_days, opts)
  return _daily(os.time() + (offset_days * 3600 * 24), opts)
end

return {
  daily_note_path = daily_note_path,
  daily = daily,
  tomorrow = tomorrow,
  yesterday = yesterday,
  today = today,
}
