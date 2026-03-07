local moment = require "obsidian.lib.moment"

local M = {}

--- Token patterns ordered from smallest to largest time unit.
--- The first match determines the increment unit.
---@type {pattern: string, field: string}[]
local TOKEN_UNITS = {
  -- Seconds (smallest unit)
  { pattern = "ss", field = "sec" },
  { pattern = "s", field = "sec" },
  -- Minutes
  { pattern = "mm", field = "min" },
  { pattern = "m", field = "min" },
  -- Hours
  { pattern = "HH", field = "hour" },
  { pattern = "hh", field = "hour" },
  { pattern = "H", field = "hour" },
  { pattern = "h", field = "hour" },
  -- Days
  { pattern = "DDDD", field = "day" },
  { pattern = "DDD", field = "day" },
  { pattern = "DD", field = "day" },
  { pattern = "Do", field = "day" },
  { pattern = "D", field = "day" },
  -- Months
  { pattern = "MMMM", field = "month" },
  { pattern = "MMM", field = "month" },
  { pattern = "MM", field = "month" },
  { pattern = "M", field = "month" },
  -- Years (largest unit)
  { pattern = "YYYY", field = "year" },
  { pattern = "GGGG", field = "year" },
  { pattern = "YY", field = "year" },
  { pattern = "GG", field = "year" },
}

--- Get the smallest time unit present in a moment.js format string.
---@param fmt string The format string (e.g., "YYYYMMDDHHmm")
---@return string field The date field to increment ("sec", "min", "hour", "day", "month", "year")
local function get_smallest_unit(fmt)
  for _, token in ipairs(TOKEN_UNITS) do
    if fmt:find(token.pattern) then
      return token.field
    end
  end
  return "day" -- fallback
end

--- Increment a timestamp by the smallest unit present in the format.
---@param timestamp integer Unix timestamp
---@param fmt string The format string
---@return integer new_timestamp
local function increment_timestamp(timestamp, fmt)
  local unit = get_smallest_unit(fmt)
  ---@type osdateparam
  local date = os.date("*t", timestamp)
  ---@diagnostic disable-next-line: need-check-nil
  date[unit] = date[unit] + 1
  return os.time(date)
end

--- Generate a unique note ID, handling collisions by incrementing timestamp.
--- When a collision is detected, the timestamp is incremented by the smallest
--- time unit present in the format (matching Obsidian app behavior).
---
---@param timestamp integer|nil Unix timestamp (defaults to os.time())
---@param fmt string The format string (e.g., "YYYYMMDDHHmm")
---@param existing_stems table<string, boolean> Map of existing file stems
---@return string id The unique note ID
---@return integer timestamp The final timestamp used
function M.generate_unique_id(timestamp, fmt, existing_stems)
  timestamp = timestamp or os.time()
  local date_id = moment.format(timestamp, fmt)

  while existing_stems[date_id] do
    timestamp = increment_timestamp(timestamp, fmt)
    date_id = moment.format(timestamp, fmt)
  end

  return date_id, timestamp
end

return M
