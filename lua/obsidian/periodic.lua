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
    get_period_start = function(datetime, opts)
      -- For daily notes, we want the start of the day
      local date = os.date("*t", datetime)
      return os.time({ year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 })
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
    offset_period = function(datetime, offset, opts)
      return datetime + (offset * 7 * 24 * 60 * 60)
    end,
    default_date_format = "%Y-W%V",
    default_alias_format = "Week %V, %Y",
  },

  monthly = {
    period_type = "monthly",
    config_key = "monthly_notes",
    get_period_start = function(datetime, opts)
      local year = tonumber(os.date("%Y", datetime))
      local month = tonumber(os.date("%m", datetime))
      return os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    offset_period = function(datetime, offset, opts)
      local year = tonumber(os.date("%Y", datetime))
      local month = tonumber(os.date("%m", datetime))

      month = month + offset
      while month > 12 do
        month = month - 12
        year = year + 1
      end
      while month < 1 do
        month = month + 12
        year = year - 1
      end

      return os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    default_date_format = "%Y-%m",
    default_alias_format = "%B %Y",
  },

  quarterly = {
    period_type = "quarterly",
    config_key = "quarterly_notes",
    get_period_start = function(datetime, opts)
      local year = tonumber(os.date("%Y", datetime))
      local month = tonumber(os.date("%m", datetime))
      -- Get the first month of the quarter
      local quarter_start_month = math.floor((month - 1) / 3) * 3 + 1
      return os.time({ year = year, month = quarter_start_month, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    offset_period = function(datetime, offset, opts)
      local year = tonumber(os.date("%Y", datetime))
      local month = tonumber(os.date("%m", datetime))

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

      return os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    default_date_format = "%Y-Q%q",
    default_alias_format = "Q%q %Y",
  },

  yearly = {
    period_type = "yearly",
    config_key = "yearly_notes",
    get_period_start = function(datetime, opts)
      local year = tonumber(os.date("%Y", datetime))
      return os.time({ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    offset_period = function(datetime, offset, opts)
      local year = tonumber(os.date("%Y", datetime))
      year = year + offset
      return os.time({ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    end,
    default_date_format = "%Y",
    default_alias_format = "%Y",
  },
}

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
---
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

return M
