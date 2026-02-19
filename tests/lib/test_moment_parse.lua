local moment = require "obsidian.lib.moment"

local new_set = MiniTest.new_set

-- Helper to check if two date tables are equal
local function date_eq(date1, date2)
  if not date1 or not date2 then
    return false
  end
  return date1.year == date2.year
    and date1.month == date2.month
    and date1.day == date2.day
    and date1.hour == date2.hour
    and date1.min == date2.min
    and date1.sec == date2.sec
end

-- Helper to check only date fields (year/month/day)
local function date_eq_ymd(date1, date2)
  if not date1 or not date2 then
    return false
  end
  return date1.year == date2.year and date1.month == date2.month and date1.day == date2.day
end

-- Expectation for date parsing
local parse_eq = MiniTest.new_expectation("parses to expected date", function(input, format, expected)
  local result = moment.parse(input, format)
  return date_eq(result, expected)
end, function(input, format, expected)
  local result = moment.parse(input, format)
  return string.format(
    "Input: %s\nFormat: %s\nExpected: %s\nGot: %s",
    input,
    format,
    vim.inspect(expected),
    vim.inspect(result)
  )
end)

-- Expectation for date parsing (year/month/day only)
local parse_eq_ymd = MiniTest.new_expectation("parses to expected date (Y/M/D)", function(input, format, expected)
  local result = moment.parse(input, format)
  return date_eq_ymd(result, expected)
end, function(input, format, expected)
  local result = moment.parse(input, format)
  return string.format(
    "Input: %s\nFormat: %s\nExpected: %s\nGot: %s",
    input,
    format,
    vim.inspect(expected),
    vim.inspect(result)
  )
end)

-- Expectation for round-trip (format then parse)
local roundtrip_eq = MiniTest.new_expectation("round-trip preserves date", function(time, format)
  local formatted = moment.format(time, format)
  local parsed = moment.parse(formatted, format)
  if not parsed then
    return false
  end
  -- Compare essential fields
  local expected = os.date("*t", time)
  return parsed.year == expected.year and parsed.month == expected.month and parsed.day == expected.day
end, function(time, format)
  local formatted = moment.format(time, format)
  local parsed = moment.parse(formatted, format)
  return string.format("Format: %s\nFormatted: %s\nParsed: %s", format, formatted, vim.inspect(parsed))
end)

-- Test date for consistent testing
local test_date = os.time {
  year = 2024,
  month = 3,
  day = 15,
  hour = 14,
  min = 30,
  sec = 45,
}

local T = new_set()

-- Year parsing tests
T["parse YYYY"] = function()
  parse_eq("2024-03-15", "YYYY-MM-DD", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("1999-12-31", "YYYY-MM-DD", { year = 1999, month = 12, day = 31, hour = 0, min = 0, sec = 0 })
end

T["parse YY current century"] = function()
  parse_eq("24-03-15", "YY-MM-DD", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
end

T["parse YY previous century"] = function()
  parse_eq("95-03-15", "YY-MM-DD", { year = 1995, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
end

-- Month parsing tests
T["parse MM padded"] = function()
  parse_eq("2024-03-15", "YYYY-MM-DD", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-12-01", "YYYY-MM-DD", { year = 2024, month = 12, day = 1, hour = 0, min = 0, sec = 0 })
end

T["parse M unpadded"] = function()
  parse_eq("2024-3-15", "YYYY-M-DD", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-12-1", "YYYY-M-D", { year = 2024, month = 12, day = 1, hour = 0, min = 0, sec = 0 })
end

T["parse MMMM full month name"] = function()
  parse_eq("15 March 2024", "D MMMM YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("January 1, 2024", "MMMM D, YYYY", { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
  parse_eq("December 25, 2024", "MMMM D, YYYY", { year = 2024, month = 12, day = 25, hour = 0, min = 0, sec = 0 })
end

T["parse MMM short month name"] = function()
  parse_eq("15 Mar 2024", "D MMM YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("Jan 1, 2024", "MMM D, YYYY", { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
  parse_eq("Dec 25, 2024", "MMM D, YYYY", { year = 2024, month = 12, day = 25, hour = 0, min = 0, sec = 0 })
end

T["parse month names case insensitive"] = function()
  parse_eq("15 march 2024", "D MMMM YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("15 MAR 2024", "D MMM YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("15 Mar 2024", "D MMM YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
end

-- Day parsing tests
T["parse DD padded"] = function()
  parse_eq("2024-03-05", "YYYY-MM-DD", { year = 2024, month = 3, day = 5, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-31", "YYYY-MM-DD", { year = 2024, month = 3, day = 31, hour = 0, min = 0, sec = 0 })
end

T["parse D unpadded"] = function()
  parse_eq("2024-03-5", "YYYY-MM-D", { year = 2024, month = 3, day = 5, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-31", "YYYY-MM-D", { year = 2024, month = 3, day = 31, hour = 0, min = 0, sec = 0 })
end

T["parse Do ordinal with st"] = function()
  parse_eq("2024-03-1st", "YYYY-MM-Do", { year = 2024, month = 3, day = 1, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-21st", "YYYY-MM-Do", { year = 2024, month = 3, day = 21, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-31st", "YYYY-MM-Do", { year = 2024, month = 3, day = 31, hour = 0, min = 0, sec = 0 })
end

T["parse Do ordinal with nd"] = function()
  parse_eq("2024-03-2nd", "YYYY-MM-Do", { year = 2024, month = 3, day = 2, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-22nd", "YYYY-MM-Do", { year = 2024, month = 3, day = 22, hour = 0, min = 0, sec = 0 })
end

T["parse Do ordinal with rd"] = function()
  parse_eq("2024-03-3rd", "YYYY-MM-Do", { year = 2024, month = 3, day = 3, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-23rd", "YYYY-MM-Do", { year = 2024, month = 3, day = 23, hour = 0, min = 0, sec = 0 })
end

T["parse Do ordinal with th"] = function()
  parse_eq("2024-03-4th", "YYYY-MM-Do", { year = 2024, month = 3, day = 4, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-11th", "YYYY-MM-Do", { year = 2024, month = 3, day = 11, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-12th", "YYYY-MM-Do", { year = 2024, month = 3, day = 12, hour = 0, min = 0, sec = 0 })
  parse_eq("2024-03-13th", "YYYY-MM-Do", { year = 2024, month = 3, day = 13, hour = 0, min = 0, sec = 0 })
end

-- Hour parsing tests
T["parse HH 24h padded"] = function()
  parse_eq("2024-03-15 09:30", "YYYY-MM-DD HH:mm", { year = 2024, month = 3, day = 15, hour = 9, min = 30, sec = 0 })
  parse_eq("2024-03-15 14:30", "YYYY-MM-DD HH:mm", { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 })
  parse_eq("2024-03-15 23:59", "YYYY-MM-DD HH:mm", { year = 2024, month = 3, day = 15, hour = 23, min = 59, sec = 0 })
end

T["parse H 24h unpadded"] = function()
  parse_eq("2024-03-15 9:30", "YYYY-MM-DD H:mm", { year = 2024, month = 3, day = 15, hour = 9, min = 30, sec = 0 })
  parse_eq("2024-03-15 14:30", "YYYY-MM-DD H:mm", { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 })
end

T["parse hh 12h padded AM"] = function()
  parse_eq(
    "2024-03-15 09:30 AM",
    "YYYY-MM-DD hh:mm A",
    { year = 2024, month = 3, day = 15, hour = 9, min = 30, sec = 0 }
  )
  parse_eq(
    "2024-03-15 12:30 AM",
    "YYYY-MM-DD hh:mm A",
    { year = 2024, month = 3, day = 15, hour = 0, min = 30, sec = 0 }
  )
end

T["parse hh 12h padded PM"] = function()
  parse_eq(
    "2024-03-15 02:30 PM",
    "YYYY-MM-DD hh:mm A",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 }
  )
  parse_eq(
    "2024-03-15 12:30 PM",
    "YYYY-MM-DD hh:mm A",
    { year = 2024, month = 3, day = 15, hour = 12, min = 30, sec = 0 }
  )
end

T["parse h 12h unpadded"] = function()
  parse_eq("2024-03-15 9:30 am", "YYYY-MM-DD h:mm a", { year = 2024, month = 3, day = 15, hour = 9, min = 30, sec = 0 })
  parse_eq(
    "2024-03-15 2:30 pm",
    "YYYY-MM-DD h:mm a",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 }
  )
end

-- Minute and second tests
T["parse mm minutes padded"] = function()
  parse_eq("2024-03-15 14:05", "YYYY-MM-DD HH:mm", { year = 2024, month = 3, day = 15, hour = 14, min = 5, sec = 0 })
  parse_eq("2024-03-15 14:59", "YYYY-MM-DD HH:mm", { year = 2024, month = 3, day = 15, hour = 14, min = 59, sec = 0 })
end

T["parse m minutes unpadded"] = function()
  parse_eq("2024-03-15 14:5", "YYYY-MM-DD HH:m", { year = 2024, month = 3, day = 15, hour = 14, min = 5, sec = 0 })
end

T["parse ss seconds padded"] = function()
  parse_eq(
    "2024-03-15 14:30:05",
    "YYYY-MM-DD HH:mm:ss",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 5 }
  )
  parse_eq(
    "2024-03-15 14:30:59",
    "YYYY-MM-DD HH:mm:ss",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 59 }
  )
end

T["parse s seconds unpadded"] = function()
  parse_eq(
    "2024-03-15 14:30:5",
    "YYYY-MM-DD HH:mm:s",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 5 }
  )
end

-- AM/PM tests
T["parse A uppercase"] = function()
  parse_eq(
    "2024-03-15 2:30 PM",
    "YYYY-MM-DD h:mm A",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 }
  )
  parse_eq("2024-03-15 2:30 AM", "YYYY-MM-DD h:mm A", { year = 2024, month = 3, day = 15, hour = 2, min = 30, sec = 0 })
end

T["parse a lowercase"] = function()
  parse_eq(
    "2024-03-15 2:30 pm",
    "YYYY-MM-DD h:mm a",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 }
  )
  parse_eq("2024-03-15 2:30 am", "YYYY-MM-DD h:mm a", { year = 2024, month = 3, day = 15, hour = 2, min = 30, sec = 0 })
end

-- Weekday tests
T["parse dddd full weekday"] = function()
  parse_eq(
    "Friday, March 15, 2024",
    "dddd, MMMM D, YYYY",
    { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 }
  )
  parse_eq(
    "Monday, January 1, 2024",
    "dddd, MMMM D, YYYY",
    { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
  )
end

T["parse ddd short weekday"] = function()
  parse_eq("Fri, March 15, 2024", "ddd, MMMM D, YYYY", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
  parse_eq("Mon, January 1, 2024", "ddd, MMMM D, YYYY", { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

-- Quarter tests
T["parse Q numeric quarter"] = function()
  parse_eq_ymd("2024-1", "YYYY-Q", { year = 2024, month = 1, day = 1 })
  parse_eq_ymd("2024-2", "YYYY-Q", { year = 2024, month = 4, day = 1 })
  parse_eq_ymd("2024-3", "YYYY-Q", { year = 2024, month = 7, day = 1 })
  parse_eq_ymd("2024-4", "YYYY-Q", { year = 2024, month = 10, day = 1 })
end

T["parse Qo ordinal quarter"] = function()
  parse_eq_ymd("2024-1st", "YYYY-Qo", { year = 2024, month = 1, day = 1 })
  parse_eq_ymd("2024-2nd", "YYYY-Qo", { year = 2024, month = 4, day = 1 })
  parse_eq_ymd("2024-3rd", "YYYY-Qo", { year = 2024, month = 7, day = 1 })
  parse_eq_ymd("2024-4th", "YYYY-Qo", { year = 2024, month = 10, day = 1 })
end

-- Localized format tests
T["parse L localized short"] = function()
  parse_eq("03/15/2024", "L", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
end

T["parse LL localized long"] = function()
  parse_eq("March 15, 2024", "LL", { year = 2024, month = 3, day = 15, hour = 0, min = 0, sec = 0 })
end

T["parse LT localized time"] = function()
  local result = moment.parse("2:30 PM", "LT")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.hour, 14)
  MiniTest.expect.equality(result.min, 30)
end

T["parse LTS localized time with seconds"] = function()
  local result = moment.parse("2:30:45 PM", "LTS")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.hour, 14)
  MiniTest.expect.equality(result.min, 30)
  MiniTest.expect.equality(result.sec, 45)
end

-- Timezone tests
T["parse Z timezone with colon"] = function()
  local result = moment.parse("2024-03-15T14:30:00+05:00", "YYYY-MM-DDTHH:mm:ssZ")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.year, 2024)
end

T["parse ZZ timezone without colon"] = function()
  local result = moment.parse("2024-03-15T14:30:00+0530", "YYYY-MM-DDTHH:mm:ssZZ")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.year, 2024)
end

T["parse Z UTC timezone"] = function()
  local result = moment.parse("2024-03-15T14:30:00Z", "YYYY-MM-DDTHH:mm:ssZ")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.year, 2024)
end

-- Unix timestamp tests
T["parse X unix seconds"] = function()
  local result = moment.parse("1710505800", "X")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.year, 2024)
end

T["parse x unix milliseconds"] = function()
  local result = moment.parse("1710505800000", "x")
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.year, 2024)
end

-- Round-trip tests
T["roundtrip YYYY-MM-DD"] = function()
  local time = os.time { year = 2024, month = 3, day = 15 }
  roundtrip_eq(time, "YYYY-MM-DD")
end

T["roundtrip full datetime"] = function()
  roundtrip_eq(test_date, "YYYY-MM-DD HH:mm:ss")
end

T["roundtrip with month names"] = function()
  local time = os.time { year = 2024, month = 3, day = 15 }
  roundtrip_eq(time, "MMMM D, YYYY")
end

T["roundtrip with ordinals"] = function()
  local time = os.time { year = 2024, month = 3, day = 15 }
  roundtrip_eq(time, "MMMM Do, YYYY")
end

T["roundtrip 12h format"] = function()
  roundtrip_eq(test_date, "YYYY-MM-DD h:mm A")
end

T["roundtrip L"] = function()
  local time = os.time { year = 2024, month = 3, day = 15 }
  roundtrip_eq(time, "L")
end

T["roundtrip LL"] = function()
  local time = os.time { year = 2024, month = 3, day = 15 }
  roundtrip_eq(time, "LL")
end

-- Error handling tests
T["error on empty input"] = function()
  local result, err = moment.parse("", "YYYY-MM-DD")
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err ~= nil, true)
end

T["error on empty format"] = function()
  local result, err = moment.parse("2024-03-15", "")
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err ~= nil, true)
end

T["error on nil input"] = function()
  local result, err = moment.parse(nil, "YYYY-MM-DD")
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err ~= nil, true)
end

-- Complex format tests
T["parse complex format with multiple tokens"] = function()
  parse_eq(
    "Friday, March 15, 2024 at 2:30 PM",
    "dddd, MMMM D, YYYY [at] h:mm A",
    { year = 2024, month = 3, day = 15, hour = 14, min = 30, sec = 0 }
  )
end

T["parse with escaped brackets"] = function()
  parse_eq("Year: 2024", "[Year:] YYYY", { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

T["parse with literal text in brackets"] = function()
  parse_eq("2024-1st quarter", "YYYY-Qo [quarter]", { year = 2024, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

return T
