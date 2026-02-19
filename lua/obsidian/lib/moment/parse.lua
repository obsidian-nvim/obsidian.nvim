local lpeg = vim.lpeg

local P, R, S, C, Ct, Cc = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cc

----------------------------------------------------
-- Locale data (must match moment.lua)
----------------------------------------------------

local MONTHS = {
  [1] = "January",
  [2] = "February",
  [3] = "March",
  [4] = "April",
  [5] = "May",
  [6] = "June",
  [7] = "July",
  [8] = "August",
  [9] = "September",
  [10] = "October",
  [11] = "November",
  [12] = "December",
}

local MONTHS_SHORT = {
  [1] = "Jan",
  [2] = "Feb",
  [3] = "Mar",
  [4] = "Apr",
  [5] = "May",
  [6] = "Jun",
  [7] = "Jul",
  [8] = "Aug",
  [9] = "Sep",
  [10] = "Oct",
  [11] = "Nov",
  [12] = "Dec",
}

local MONTH_NAME_TO_NUM = {}
for num, name in pairs(MONTHS) do
  MONTH_NAME_TO_NUM[name:lower()] = num
end
for num, name in pairs(MONTHS_SHORT) do
  MONTH_NAME_TO_NUM[name:lower()] = num
end

local WEEKDAYS = {
  [1] = "Sunday",
  [2] = "Monday",
  [3] = "Tuesday",
  [4] = "Wednesday",
  [5] = "Thursday",
  [6] = "Friday",
  [7] = "Saturday",
}

local WEEKDAYS_SHORT = {
  [1] = "Sun",
  [2] = "Mon",
  [3] = "Tue",
  [4] = "Wed",
  [5] = "Thu",
  [6] = "Fri",
  [7] = "Sat",
}

local WEEKDAY_NAME_TO_NUM = {}
for num, name in pairs(WEEKDAYS) do
  WEEKDAY_NAME_TO_NUM[name:lower()] = num
end
for num, name in pairs(WEEKDAYS_SHORT) do
  WEEKDAY_NAME_TO_NUM[name:lower()] = num
end

----------------------------------------------------
-- Case-insensitive pattern builder
----------------------------------------------------

local function case_insensitive(str)
  local pattern = P ""
  for i = 1, #str do
    local c = str:sub(i, i)
    local lower = c:lower()
    local upper = c:upper()
    if lower == upper then
      pattern = pattern * P(c)
    else
      pattern = pattern * (P(lower) + P(upper))
    end
  end
  return pattern
end

----------------------------------------------------
-- Ordinal suffix patterns (Do, Qo, Wo)
----------------------------------------------------

local function ordinal_pattern()
  local digit = R "09"
  local number = C(digit ^ 1)
  local suffix = case_insensitive "st" + case_insensitive "nd" + case_insensitive "rd" + case_insensitive "th"
  return number * suffix / function(n)
    return tonumber(n)
  end
end

----------------------------------------------------
-- Month name patterns
----------------------------------------------------

local function build_month_pattern(long_names, short_names)
  local pattern = P(false)

  -- Add long names first (longest match first)
  for _, name in ipairs(long_names) do
    pattern = pattern + case_insensitive(name) * Cc(MONTH_NAME_TO_NUM[name:lower()])
  end

  -- Then short names
  for _, name in ipairs(short_names) do
    pattern = pattern + case_insensitive(name) * Cc(MONTH_NAME_TO_NUM[name:lower()])
  end

  return pattern
end

local month_name_pattern = build_month_pattern(MONTHS, MONTHS_SHORT)

----------------------------------------------------
-- Weekday name patterns
----------------------------------------------------

local function build_weekday_pattern(long_names, short_names)
  local pattern = P(false)

  -- Add long names first
  for _, name in ipairs(long_names) do
    pattern = pattern + case_insensitive(name) * Cc(WEEKDAY_NAME_TO_NUM[name:lower()])
  end

  -- Then short names
  for _, name in ipairs(short_names) do
    pattern = pattern + case_insensitive(name) * Cc(WEEKDAY_NAME_TO_NUM[name:lower()])
  end

  return pattern
end

local weekday_pattern = build_weekday_pattern(WEEKDAYS, WEEKDAYS_SHORT)
local weekday_short_2char_pattern = case_insensitive "Su"
  + case_insensitive "Mo"
  + case_insensitive "Tu"
  + case_insensitive "We"
  + case_insensitive "Th"
  + case_insensitive "Fr"
  + case_insensitive "Sa"

----------------------------------------------------
-- Year pivot for YY format (moment.js uses ±68 years)
----------------------------------------------------

local CURRENT_YEAR = tonumber(os.date "%Y")
local YEAR_PIVOT = 68

local function parse_two_digit_year(yy_str)
  local yy = tonumber(yy_str)
  local current_year_last_two = CURRENT_YEAR % 100
  local century = math.floor(CURRENT_YEAR / 100)

  -- Standard pivot logic:
  -- If yy is far in the future (> current + pivot), it's from previous century
  -- If yy is far in the past (< current - pivot), it's from next century
  -- Otherwise, it's from current century
  if yy > current_year_last_two + YEAR_PIVOT then
    -- e.g., current is 24, yy is 95, pivot is 68
    -- 95 > 24 + 68 = 92, so 95 is from 1995 (previous century)
    return (century - 1) * 100 + yy
  elseif yy < current_year_last_two - YEAR_PIVOT then
    -- e.g., current is 24, yy is 05, pivot is 68
    -- 05 < 24 - 68 = -44, so 05 is from 2105 (next century)
    -- But wait, that doesn't make sense for 1980...
    -- Actually, this case won't trigger for 1980
    return (century + 1) * 100 + yy
  else
    return century * 100 + yy
  end
end

----------------------------------------------------
-- Token pattern builders
----------------------------------------------------

local token_patterns = {}

-- Year patterns
token_patterns["YYYY"] = function()
  return C(R "09" ^ 4) / tonumber
end

token_patterns["YY"] = function()
  return C(R "09" ^ 2) / parse_two_digit_year
end

-- Month patterns
token_patterns["MMMM"] = function()
  return month_name_pattern
end

token_patterns["MMM"] = function()
  return month_name_pattern
end

token_patterns["MM"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["M"] = function()
  -- Match 1-9 or 10-12, preferring 2 digits
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

-- Day patterns
token_patterns["DD"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["D"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

token_patterns["Do"] = function()
  return ordinal_pattern()
end

token_patterns["DDD"] = function()
  return (C(R "09" ^ 3) + C(R "09" ^ 2) + C(R "09")) / tonumber
end

token_patterns["DDDD"] = function()
  return C(R "09" ^ 3) / tonumber
end

-- Hour patterns (24-hour)
token_patterns["HH"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["H"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

-- Hour patterns (12-hour)
token_patterns["hh"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["h"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

-- Minute patterns
token_patterns["mm"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["m"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

-- Second patterns
token_patterns["ss"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["s"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

-- AM/PM patterns
token_patterns["A"] = function()
  return (case_insensitive "AM" + case_insensitive "PM") / function(ampm)
    return ampm:lower() == "am"
  end
end

token_patterns["a"] = function()
  return (case_insensitive "am" + case_insensitive "pm") / function(ampm)
    return ampm:lower() == "am"
  end
end

-- Weekday patterns
token_patterns["dddd"] = function()
  return weekday_pattern
end

token_patterns["ddd"] = function()
  return weekday_pattern
end

token_patterns["dd"] = function()
  -- 2-character weekday
  return weekday_short_2char_pattern
    / function(wd)
      local map = { su = 1, mo = 2, tu = 3, we = 4, th = 5, fr = 6, sa = 7 }
      return map[wd:lower()]
    end
end

token_patterns["d"] = function()
  return C(R "06") / function(n)
    return tonumber(n) + 1
  end -- 0-6 to 1-7
end

token_patterns["E"] = function()
  return C(R "17") / tonumber -- ISO weekday 1-7
end

-- Week of year
token_patterns["w"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

token_patterns["ww"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["W"] = function()
  return (C(R "09" ^ 2) + C(R "09")) / tonumber
end

token_patterns["WW"] = function()
  return C(R "09" ^ 2) / tonumber
end

token_patterns["Wo"] = function()
  return ordinal_pattern()
end

-- Quarter
token_patterns["Q"] = function()
  return C(R "14") / tonumber
end

token_patterns["Qo"] = function()
  return ordinal_pattern()
end

-- ISO week year
token_patterns["GGGG"] = function()
  return C(R "09" ^ 4) / tonumber
end

token_patterns["GG"] = function()
  return C(R "09" ^ 2) / parse_two_digit_year
end

-- Timezone patterns
token_patterns["Z"] = function()
  -- Format: +05:00, -08:00, or Z (UTC)
  local sign = S "+-"
  local hours = R "09" ^ 2
  local minutes = R "09" ^ 2
  local offset_pattern = C(sign * hours * P ":" * minutes)
    / function(tz)
      local offset_sign = tz:sub(1, 1) == "+" and 1 or -1
      local offset_hours = tonumber(tz:sub(2, 3))
      local offset_mins = tonumber(tz:sub(5, 6))
      return offset_sign * (offset_hours * 60 + offset_mins) * 60
    end
  local utc_pattern = case_insensitive "Z" * Cc(0) -- UTC is 0 offset
  return offset_pattern + utc_pattern
end

token_patterns["ZZ"] = function()
  -- Format: +0500, -0800, or Z (UTC)
  local sign = S "+-"
  local digits = R "09" ^ 4
  local offset_pattern = C(sign * digits)
    / function(tz)
      local offset_sign = tz:sub(1, 1) == "+" and 1 or -1
      local offset_hours = tonumber(tz:sub(2, 3))
      local offset_mins = tonumber(tz:sub(4, 5))
      return offset_sign * (offset_hours * 60 + offset_mins) * 60
    end
  local utc_pattern = case_insensitive "Z" * Cc(0) -- UTC is 0 offset
  return offset_pattern + utc_pattern
end

-- Unix timestamps
token_patterns["X"] = function()
  return C(R "09" ^ 1) / tonumber
end

token_patterns["x"] = function()
  return C(R "09" ^ 1) / function(n)
    return math.floor(tonumber(n) / 1000)
  end
end

----------------------------------------------------
-- Build parser from format string
----------------------------------------------------

local function token(name)
  return P(name) / function()
    return { type = "token", value = name }
  end
end

-- Same token pattern as moment.lua
-- Order matters: longer tokens first, then shorter ones
local token_pattern = token "YYYY"
  + token "GGGG"
  + token "MMMM"
  + token "dddd"
  + token "DDDD"
  + token "LLLL"
  + token "MMM"
  + token "ddd"
  + token "DDD"
  + token "LTS"
  + token "LLL"
  + token "GG"
  + token "YY"
  + token "MM"
  + token "DD"
  + token "Do"
  + token "HH"
  + token "hh"
  + token "ZZ"
  + token "Qo"
  + token "Wo"
  + token "WW"
  + token "ww"
  + token "mm"
  + token "ss"
  + token "dd"
  + token "LL"
  + token "LT"
  + token "M"
  + token "D"
  + token "H"
  + token "h"
  + token "m"
  + token "s"
  + token "Z"
  + token "W"
  + token "w"
  + token "A"
  + token "a"
  + token "d"
  + token "E"
  + token "Q"
  + token "X"
  + token "x"
  + token "L"

local literal = P "[" * C((1 - P "]") ^ 0) * P "]" / function(s)
  return { type = "literal", value = s }
end

local text = C(1) / function(s)
  return { type = "text", value = s }
end

local format_grammar = Ct((literal + token_pattern + text) ^ 0)

local LONG_DATE_FORMAT = {
  L = "MM/DD/YYYY",
  LL = "MMMM D, YYYY",
  LLL = "MMMM D, YYYY h:mm A",
  LLLL = "dddd, MMMM D, YYYY h:mm A",
  LT = "h:mm A",
  LTS = "h:mm:ss A",
}

local function expand_localized(ast)
  local out = {}

  for _, node in ipairs(ast) do
    if node.type == "token" and LONG_DATE_FORMAT[node.value] then
      local expanded = format_grammar:match(LONG_DATE_FORMAT[node.value])
      for _, e in ipairs(expanded) do
        out[#out + 1] = e
      end
    else
      out[#out + 1] = node
    end
  end

  return out
end

----------------------------------------------------
-- Build the parsing grammar
----------------------------------------------------

-- Default values for unspecified fields
---@type osdateparam
local DEFAULTS = {
  year = CURRENT_YEAR,
  month = 1,
  day = 1,
  hour = 0,
  min = 0,
  sec = 0,
  isdst = false,
}

---@param input string
---@param fmt string
---@return osdateparam|nil, string|nil
return function(input, fmt)
  if not input or input == "" then
    return nil, "Empty input"
  end
  if not fmt or fmt == "" then
    return nil, "Empty format"
  end

  -- Parse format string into AST
  local ast = format_grammar:match(fmt)
  if not ast then
    return nil, "Invalid format string"
  end

  -- Expand localized formats
  ast = expand_localized(ast)

  -- Build parsing patterns
  local patterns = {}

  for _, node in ipairs(ast) do
    if node.type == "token" then
      local pattern_builder = token_patterns[node.value]
      if pattern_builder then
        -- Wrap pattern to capture with token name
        local wrapped = pattern_builder() / function(v)
          return { token = node.value, value = v }
        end
        patterns[#patterns + 1] = wrapped
      else
        return nil, "Unknown token: " .. node.value
      end
    elseif node.type == "literal" then
      -- Escape special LPeg characters in literals
      local escaped = node.value:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
      patterns[#patterns + 1] = P(escaped)
    elseif node.type == "text" then
      patterns[#patterns + 1] = P(node.value)
    end
  end

  if #patterns == 0 then
    return nil, "No patterns built"
  end

  -- Combine all patterns
  local parser = P ""
  for _, p in ipairs(patterns) do
    parser = parser * p
  end
  parser = parser * P(-1) -- Ensure full match
  parser = Ct(parser) -- Capture all results as a table

  -- Parse input
  local results = parser:match(input)

  if not results or #results == 0 then
    return nil, "Parse failed"
  end

  -- Extract values from captures
  local date_fields = {}
  local has_am_pm = nil
  local hour_12 = nil
  local timezone_offset = nil
  local unix_timestamp = nil

  for _, result in ipairs(results) do
    if type(result) == "table" and result.token then
      local token_name = result.token
      local value = result.value

      -- Map tokens to date fields
      if token_name == "YYYY" or token_name == "GGGG" then
        date_fields.year = value
      elseif token_name == "YY" or token_name == "GG" then
        date_fields.year = value
      elseif token_name == "MMMM" or token_name == "MMM" or token_name == "MM" or token_name == "M" then
        date_fields.month = value
      elseif token_name == "DD" or token_name == "D" or token_name == "Do" then
        date_fields.day = value
      elseif token_name == "HH" or token_name == "H" then
        date_fields.hour = value
        hour_12 = false
      elseif token_name == "hh" or token_name == "h" then
        hour_12 = value
      elseif token_name == "mm" or token_name == "m" then
        date_fields.min = value
      elseif token_name == "ss" or token_name == "s" then
        date_fields.sec = value
      elseif token_name == "A" or token_name == "a" then
        has_am_pm = value -- true for AM, false for PM
      elseif token_name == "d" or token_name == "E" then
        date_fields.wday = value
      elseif token_name == "Q" or token_name == "Qo" then
        -- Quarter: 1-4 -> convert to month (1, 4, 7, 10)
        local quarter = value
        date_fields.month = (quarter - 1) * 3 + 1
      elseif token_name == "Z" or token_name == "ZZ" then
        timezone_offset = value
      elseif token_name == "X" or token_name == "x" then
        unix_timestamp = value
      end
    end
  end

  -- Handle 12-hour format conversion
  if hour_12 then
    if has_am_pm == false then -- PM
      date_fields.hour = (hour_12 % 12) + 12
    else -- AM or unspecified
      date_fields.hour = hour_12 % 12
    end
  end

  -- Handle Unix timestamp (overrides everything else)
  if unix_timestamp then
    local date = os.date("*t", unix_timestamp)
    if timezone_offset then
      date.hour = date.hour + math.floor(timezone_offset / 3600)
    end
    return date
  end

  -- Apply defaults
  for field, default in pairs(DEFAULTS) do
    if date_fields[field] == nil then
      date_fields[field] = default
    end
  end

  -- Validate date
  local time = os.time(date_fields)
  if not time then
    return nil, "Invalid date"
  end

  -- Convert to table
  local result = os.date("*t", time)

  -- Apply timezone offset if provided
  if timezone_offset then
    result.hour = result.hour - math.floor(timezone_offset / 3600)
  end

  return result
end
