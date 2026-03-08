-- TODO: This test suite covers only commonly-used format tokens, not exhaustive format combinations
-- TODO: Time-only formats (LT, LTS) are skipped; they default to current date which makes round-trip testing complex
-- TODO: Timezone-sensitive tests are skipped due to environment-dependent behavior

local moment = require "obsidian.lib.moment"

local new_set = MiniTest.new_set

-- Helper to convert date table to unix timestamp
local function date_to_timestamp(date)
  return os.time(date)
end

-- Expectation for round-trip test (checks only the fields encoded in the format)
local roundtrip_eq = MiniTest.new_expectation(
  "round-trip format→parse→date preserves encoded values",
  function(format_str, test_date)
    -- Determine which fields are encoded in the format
    local has_year = format_str:find "YYYY" or format_str:find "YY"
    local has_month = format_str:find "MMMM" or format_str:find "MMM" or format_str:find "MM" or format_str:find "M"
    local has_day = format_str:find "DD" or format_str:find "D" or format_str:find "Do"
    local has_hour = format_str:find "HH" or format_str:find "hh" or format_str:find "H" or format_str:find "h"
    local has_min = format_str:find "mm"
    local has_sec = format_str:find "ss"

    local timestamp = date_to_timestamp(test_date)
    local formatted = moment.format(timestamp, format_str)
    local parsed = moment.parse(formatted, format_str)

    -- Check only the fields that are in the format
    local matches = true
    if has_year and parsed.year ~= test_date.year then
      matches = false
    end
    if has_month and parsed.month ~= test_date.month then
      matches = false
    end
    if has_day and parsed.day ~= test_date.day then
      matches = false
    end
    if has_hour and parsed.hour ~= test_date.hour then
      matches = false
    end
    if has_min and parsed.min ~= test_date.min then
      matches = false
    end
    if has_sec and parsed.sec ~= test_date.sec then
      matches = false
    end

    return matches
  end,
  function(format_str, test_date)
    local timestamp = date_to_timestamp(test_date)
    local formatted = moment.format(timestamp, format_str)
    local parsed = moment.parse(formatted, format_str)
    return string.format(
      "Format: %s\nFormatted: %s\nOriginal date: %s\nParsed back: %s",
      format_str,
      formatted,
      vim.inspect(test_date),
      vim.inspect(parsed)
    )
  end
)

-- Test dates covering common scenarios
local test_dates = {
  -- Mid-range dates (all in January to avoid DST issues)
  { year = 2024, month = 1, day = 15, hour = 14, min = 30, sec = 45, wday = 2, yday = 15, isdst = false },
  { year = 2023, month = 1, day = 31, hour = 23, min = 59, sec = 59, wday = 3, yday = 31, isdst = false },
  { year = 2000, month = 1, day = 1, hour = 0, min = 0, sec = 0, wday = 7, yday = 1, isdst = false },

  -- Month boundaries (all in January/February)
  { year = 2024, month = 2, day = 29, hour = 12, min = 0, sec = 0, wday = 5, yday = 60, isdst = false }, -- Leap year
  { year = 2023, month = 2, day = 28, hour = 12, min = 0, sec = 0, wday = 3, yday = 59, isdst = false }, -- Non-leap

  -- Different months (but all in winter to avoid DST)
  { year = 2024, month = 12, day = 15, hour = 9, min = 15, sec = 30, wday = 1, yday = 350, isdst = false },
  { year = 2024, month = 1, day = 5, hour = 8, min = 30, sec = 0, wday = 6, yday = 5, isdst = false },

  -- Time variations (all in January)
  { year = 2024, month = 1, day = 15, hour = 0, min = 0, sec = 0, wday = 2, yday = 15, isdst = false },
  { year = 2024, month = 1, day = 15, hour = 12, min = 30, sec = 15, wday = 2, yday = 15, isdst = false },
  { year = 2024, month = 1, day = 15, hour = 11, min = 45, sec = 30, wday = 2, yday = 15, isdst = false },
  { year = 2024, month = 1, day = 15, hour = 1, min = 5, sec = 5, wday = 2, yday = 15, isdst = false },
}

-- Common format strings (subset of moment.js tokens)
-- NOTE: Formats must include all date components (YYYY, MM/M, DD/D) to preserve date on round-trip
-- because parsing loses granularity if not all components are specified
local common_formats = {
  -- Full date+time
  "YYYY-MM-DD HH:mm:ss",
  "YYYY-MM-DD HH:mm",
  "YYYY/MM/DD HH:mm:ss",

  -- Date only
  "YYYY-MM-DD",
  "MM/DD/YYYY",
  "DD/MM/YYYY",
  "YYYY/MM/DD",

  -- With short names
  "MMM DD, YYYY",
  "MMM D, YYYY",
  "MMMM D, YYYY",
  "D MMMM YYYY",

  -- With AM/PM (includes full date)
  "YYYY-MM-DD h:mm A",
  "YYYY-MM-DD h:mm a",
  "MM/DD/YYYY h:mm A",
  "MMMM DD, YYYY h:mm A",

  -- With day names (includes full date)
  "dddd, MMMM D, YYYY",
  "ddd MMM DD YYYY",
  "YYYY-MM-DD dddd HH:mm",

  -- Ordinals (with full date components)
  "MMMM Do, YYYY",
  "Do MMMM YYYY",
}

local T = new_set()

-- Generate round-trip tests for each format with each test date
for i, date in ipairs(test_dates) do
  for j, format in ipairs(common_formats) do
    local test_name = string.format(
      "round-trip_%d_%d: %s with date {%04d-%02d-%02d %02d:%02d:%02d}",
      i,
      j,
      format,
      date.year,
      date.month,
      date.day,
      date.hour,
      date.min,
      date.sec
    )

    T[test_name] = function()
      roundtrip_eq(format, date)
    end
  end
end

return T
