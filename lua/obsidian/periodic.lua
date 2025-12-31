local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"

local M = {}

---@class obsidian.PeriodicConfig
---@field period_type string The type of period (daily, weekly, monthly, quarterly, yearly)
---@field config_key string The key in Obsidian.opts for this period's config
---@field get_period_start fun(datetime: integer, opts: table|?): integer Function to get the start of the period
---@field offset_period fun(datetime: integer, offset: integer, opts: table|?): integer Function to offset the period
---@field default_date_format string Default date format for the filename
---@field default_alias_format string Default alias format for display

--- Period configurations
M.PERIODS = {
  daily = {
    period_type = "daily",
    config_key = "daily_notes",
    get_period_start = function(datetime)
      -- For daily notes, we want the start of the day
      local date = os.date("*t", datetime)
      return os.time { year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 }
    end,
    offset_period = function(datetime, offset, opts)
      local use_workdays = opts and opts.workdays_only or false
      if offset == 0 then
        return datetime
      elseif offset == 1 and use_workdays then
        return util.working_day_after(datetime)
      elseif offset == -1 and use_workdays then
        return util.working_day_before(datetime)
      else
        return datetime + (offset * 24 * 60 * 60)
      end
    end,
    default_date_format = "%Y-%m-%d",
    default_alias_format = "%A %B %-d, %Y",
  },

  weekly = {
    period_type = "weekly",
    config_key = "weekly_notes",
    get_period_start = function(datetime, opts)
      local start_of_week = (opts and opts.start_of_week) or 1 -- Default to Monday
      local current_day = tonumber(os.date("%w", datetime))
      local days_to_subtract = (current_day - start_of_week + 7) % 7
      return datetime - (days_to_subtract * 24 * 60 * 60)
    end,
    offset_period = function(datetime, offset)
      return datetime + (offset * 7 * 24 * 60 * 60)
    end,
    default_date_format = "%G-W%V",
    default_alias_format = "Week %V, %G",
  },

  monthly = {
    period_type = "monthly",
    config_key = "monthly_notes",
    get_period_start = function(datetime)
      local year = tonumber(os.date("%Y", datetime)) or 0
      local month = tonumber(os.date("%m", datetime)) or 0
      return os.time { year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    offset_period = function(datetime, offset)
      local year = tonumber(os.date("%Y", datetime)) or 0
      local month = tonumber(os.date("%m", datetime)) or 0

      month = month + offset
      while month > 12 do
        month = month - 12
        year = year + 1
      end
      while month < 1 do
        month = month + 12
        year = year - 1
      end

      return os.time { year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    default_date_format = "%Y-%m",
    default_alias_format = "%B %Y",
  },

  quarterly = {
    period_type = "quarterly",
    config_key = "quarterly_notes",
    get_period_start = function(datetime)
      local year = tonumber(os.date("%Y", datetime)) or 0
      local month = tonumber(os.date("%m", datetime))
      -- Get the first month of the quarter
      local quarter_start_month = math.floor((month - 1) / 3) * 3 + 1
      return os.time { year = year, month = quarter_start_month, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    offset_period = function(datetime, offset)
      local year = tonumber(os.date("%Y", datetime)) or 0
      local month = tonumber(os.date("%m", datetime)) or 0

      -- Move by quarters (3 months)
      month = month + (offset * 3)
      while month > 12 do
        month = month - 12
        year = year + 1
      end
      while month < 1 do
        month = month + 12
        year = year - 1
      end

      return os.time { year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    default_date_format = "%Y-Q%q",
    default_alias_format = "Q%q %Y",
  },

  yearly = {
    period_type = "yearly",
    config_key = "yearly_notes",
    get_period_start = function(datetime)
      local year = tonumber(os.date("%Y", datetime)) or 0
      return os.time { year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    offset_period = function(datetime, offset)
      local year = tonumber(os.date("%Y", datetime))
      year = year + offset
      return os.time { year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    end,
    default_date_format = "%Y",
    default_alias_format = "%Y",
  },
}

--- Periodic class for period-based notes
---@class Periodic
---@field period_type string
---@field config_key string
---@field get_period_start fun(datetime: integer, opts: table|?): integer
---@field offset_period fun(datetime: integer, offset: integer, opts: table|?): integer
---@field default_date_format string
---@field default_alias_format string
local Periodic = {}
Periodic.__index = Periodic

--- Create a new Periodic instance
---@param period_config obsidian.PeriodicConfig
---@return Periodic
function Periodic.new(period_config)
  local instance = {
    period_type = period_config.period_type,
    config_key = period_config.config_key,
    get_period_start = period_config.get_period_start,
    offset_period = period_config.offset_period,
    default_date_format = period_config.default_date_format,
    default_alias_format = period_config.default_alias_format,
  }
  return setmetatable(instance, Periodic)
end

--- Get the path to a periodic note
---@param datetime integer|?
---@return obsidian.Path, string
function Periodic:note_path(datetime)
  return M.periodic_note_path(self, datetime)
end

--- Get the current period's note
---@return obsidian.Note
function Periodic:this()
  return M.periodic_note(self, os.time(), {})
end

--- Get the previous period's note
---@return obsidian.Note
function Periodic:last()
  local config = Obsidian.opts[self.config_key]
  local current = self.get_period_start(os.time(), config)
  local last = self.offset_period(current, -1, config)
  return M.periodic_note(self, last, {})
end

--- Get the next period's note
---@return obsidian.Note
function Periodic:next()
  local config = Obsidian.opts[self.config_key]
  local current = self.get_period_start(os.time(), config)
  local next = self.offset_period(current, 1, config)
  return M.periodic_note(self, next, {})
end

--- Get a period note with offset
---@param offset integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---@return obsidian.Note
function Periodic:period(offset, opts)
  local config = Obsidian.opts[self.config_key]
  local current = self.get_period_start(os.time(), config)
  local target = self.offset_period(current, offset, config)
  return M.periodic_note(self, target, opts)
end

--- Open a picker to select a period note
---@param offset_start integer
---@param offset_end integer
function Periodic:pick(offset_start, offset_end)
  local log = require "obsidian.log"
  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  local config = Obsidian.opts[self.config_key]
  local entries = {}

  for offset = offset_end, offset_start, -1 do
    local current = self.get_period_start(os.time(), config)
    local datetime = self.offset_period(current, offset, config)
    local path = self:note_path(datetime)

    -- Generate alias with proper formatting
    local alias
    if self.period_type == "quarterly" then
      local month = tonumber(os.date("%m", datetime))
      local quarter = math.floor((month - 1) / 3) + 1
      local formatted = (config.alias_format or self.default_alias_format):gsub("%%q", tostring(quarter))
      alias = tostring(os.date(formatted, datetime))
    else
      alias = tostring(os.date(config.alias_format or self.default_alias_format, datetime))
    end

    -- Add special labels
    if offset == 0 then
      alias = alias .. " @this-" .. self.period_type
    elseif offset == -1 then
      alias = alias .. " @last-" .. self.period_type
    elseif offset == 1 then
      alias = alias .. " @next-" .. self.period_type
    end

    if not path:is_file() then
      alias = alias .. " ➡️ create"
    end

    entries[#entries + 1] = {
      value = offset,
      display = alias,
      ordinal = alias,
      filename = tostring(path),
    }
  end

  -- Capitalize first letter of period type for title
  local title = self.period_type:gsub("^%l", string.upper) .. "s"

  picker:pick(entries, {
    prompt_title = title,
    callback = function(entry)
      local note = self:period(entry.value, {})
      note:open()
    end,
  })
end

--- Get the path to a periodic note.
---
---@param period_config obsidian.PeriodicConfig
---@param datetime integer|?
---
---@return obsidian.Path, string (Path, ID) The path and ID of the note.
M.periodic_note_path = function(period_config, datetime)
  datetime = datetime and datetime or os.time()

  ---@type obsidian.Path
  local path = Path.new(Obsidian.dir)

  local options = Obsidian.opts
  local config = options[period_config.config_key]

  -- Get the start of the period for consistent identification
  local period_start = period_config.get_period_start(datetime, config)

  if config.folder ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / config.folder
  elseif options.notes_subdir ~= nil then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    path = path / options.notes_subdir
  end

  local id
  if config.date_format ~= nil then
    id = tostring(os.date(config.date_format, period_start))
  else
    -- Custom formatting for quarterly since %q is not standard
    if period_config.period_type == "quarterly" then
      local month = tonumber(os.date("%m", period_start))
      local quarter = math.floor((month - 1) / 3) + 1
      local year = os.date("%Y", period_start)
      id = string.format("%s-Q%d", year, quarter)
    else
      id = tostring(os.date(period_config.default_date_format, period_start))
    end
  end

  path = path / (id .. ".md")

  -- ID may contain additional path components, so make sure we use the stem.
  id = path.stem

  return path, id
end

--- Open (or create) a periodic note.
---
---@param period_config obsidian.PeriodicConfig
---@param datetime integer
---@param opts { no_write: boolean|?, load: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note
---
M.periodic_note = function(period_config, datetime, opts)
  opts = opts or {}

  local path, id = M.periodic_note_path(period_config, datetime)

  local options = Obsidian.opts
  local config = options[period_config.config_key]

  -- Get the start of the period for alias
  local period_start = period_config.get_period_start(datetime, config)

  ---@type string|?
  local alias
  if config.alias_format ~= nil then
    -- Custom formatting for quarterly
    if period_config.period_type == "quarterly" then
      local month = tonumber(os.date("%m", period_start))
      local quarter = math.floor((month - 1) / 3) + 1
      local formatted = config.alias_format:gsub("%%q", tostring(quarter))
      alias = tostring(os.date(formatted, period_start))
    else
      alias = tostring(os.date(config.alias_format, period_start))
    end
  end

  ---@type obsidian.Note
  local note
  if path:exists() then
    note = Note.from_file(path, opts.load)
  else
    note = Note.create {
      id = id,
      aliases = {},
      tags = config.default_tags or {},
      dir = path:parent(),
    }

    if alias then
      note:add_alias(alias)
      note.title = alias
    end

    if not opts.no_write then
      note:write { template = config.template }
    end
  end

  return note
end

--- Create helper functions for a specific period type
--- @deprecated Use the singleton instances (M.daily, M.weekly, etc.) instead
---@param period_config obsidian.PeriodicConfig
---@return table Functions: this_period, last_period, next_period, period, period_note_path
M.create_period_functions = function(period_config)
  local functions = {}

  -- Get path function
  functions.period_note_path = function(datetime)
    return M.periodic_note_path(period_config, datetime)
  end

  -- Current period
  functions.this_period = function()
    return M.periodic_note(period_config, os.time(), {})
  end

  -- Last period
  functions.last_period = function()
    local config = Obsidian.opts[period_config.config_key]
    local current = period_config.get_period_start(os.time(), config)
    local last = period_config.offset_period(current, -1, config)
    return M.periodic_note(period_config, last, {})
  end

  -- Next period
  functions.next_period = function()
    local config = Obsidian.opts[period_config.config_key]
    local current = period_config.get_period_start(os.time(), config)
    local next = period_config.offset_period(current, 1, config)
    return M.periodic_note(period_config, next, {})
  end

  -- Period with offset
  functions.period = function(offset, opts)
    local config = Obsidian.opts[period_config.config_key]
    local current = period_config.get_period_start(os.time(), config)
    local target = period_config.offset_period(current, offset, config)
    return M.periodic_note(period_config, target, opts)
  end

  return functions
end

--- Singleton instances for each period type
M.daily = Periodic.new(M.PERIODS.daily)
M.weekly = Periodic.new(M.PERIODS.weekly)
M.monthly = Periodic.new(M.PERIODS.monthly)
M.quarterly = Periodic.new(M.PERIODS.quarterly)
M.yearly = Periodic.new(M.PERIODS.yearly)

-- Backward-compatible module exports
-- These replicate the APIs from the old daily/, weekly/, etc. modules

--- Daily note functions (backward compatible with obsidian.daily)
M.daily_note_path = function(datetime)
  return M.daily:note_path(datetime)
end
M.today = function()
  return M.daily:this()
end
M.yesterday = function()
  return M.daily:last()
end
M.tomorrow = function()
  return M.daily:next()
end
M.daily_fn = function(offset, opts)
  return M.daily:period(offset, opts)
end
M.daily_pick = function(offset_start, offset_end, callback)
  ---@type obsidian.PickerEntry[]
  local dailies = {}
  for offset = offset_start, offset_end, 1 do
    local datetime = os.time() + (offset * 3600 * 24)
    local daily_note_path = M.daily_note_path(datetime)
    local daily_note_alias = tostring(os.date(Obsidian.opts.daily_notes.alias_format or "%A %B %-d, %Y", datetime))
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

  Obsidian.picker.pick(dailies, {
    prompt_title = "Dailies",
    callback = function(entry)
      local note = M.daily_fn(entry.user_data, {})
      callback(note)
    end,
  })
end

--- Weekly note functions (backward compatible with obsidian.weekly)
M.weekly_note_path = function(datetime)
  return M.weekly:note_path(datetime)
end
M.this_week = function()
  return M.weekly:this()
end
M.last_week = function()
  return M.weekly:last()
end
M.next_week = function()
  return M.weekly:next()
end
M.weekly_fn = function(offset, opts)
  return M.weekly:period(offset, opts)
end

--- Monthly note functions (backward compatible with obsidian.monthly)
M.monthly_note_path = function(datetime)
  return M.monthly:note_path(datetime)
end
M.this_month = function()
  return M.monthly:this()
end
M.last_month = function()
  return M.monthly:last()
end
M.next_month = function()
  return M.monthly:next()
end
M.monthly_fn = function(offset, opts)
  return M.monthly:period(offset, opts)
end

--- Quarterly note functions (backward compatible with obsidian.quarterly)
M.quarterly_note_path = function(datetime)
  return M.quarterly:note_path(datetime)
end
M.this_quarter = function()
  return M.quarterly:this()
end
M.last_quarter = function()
  return M.quarterly:last()
end
M.next_quarter = function()
  return M.quarterly:next()
end
M.quarterly_fn = function(offset, opts)
  return M.quarterly:period(offset, opts)
end

--- Yearly note functions (backward compatible with obsidian.yearly)
M.yearly_note_path = function(datetime)
  return M.yearly:note_path(datetime)
end
M.this_year = function()
  return M.yearly:this()
end
M.last_year = function()
  return M.yearly:last()
end
M.next_year = function()
  return M.yearly:next()
end
M.yearly_fn = function(offset, opts)
  return M.yearly:period(offset, opts)
end

return M
