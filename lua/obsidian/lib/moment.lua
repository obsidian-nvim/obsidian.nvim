-- moment_lpeg.lua
local lpeg = vim.lpeg

local P, C, Ct = lpeg.P, lpeg.C, lpeg.Ct

-- --------------------------------------------------
-- Locale data (can be swapped later)
-- --------------------------------------------------

local MONTHS = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
}

local MONTHS_SHORT = {
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
}

local WEEKDAYS = {
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
}

local WEEKDAYS_SHORT = {
  "Sun",
  "Mon",
  "Tue",
  "Wed",
  "Thu",
  "Fri",
  "Sat",
}

-- --------------------------------------------------
-- Token handlers
-- --------------------------------------------------

local handlers = {}

local function ordinal_suffix(n)
  local mod100 = n % 100
  if mod100 >= 11 and mod100 <= 13 then
    return "th"
  end
  local mod10 = n % 10
  if mod10 == 1 then
    return "st"
  elseif mod10 == 2 then
    return "nd"
  elseif mod10 == 3 then
    return "rd"
  end
  return "th"
end

local function iso_weekday(wday)
  return ((wday + 5) % 7) + 1
end

local function week_of_year(date)
  local jan1 = os.date("*t", os.time { year = date.year, month = 1, day = 1 })
  return math.floor((date.yday + (jan1.wday - 1) - 1) / 7) + 1
end

local function iso_week(date, time)
  local wday = iso_weekday(date.wday)
  local thursday = time + (4 - wday) * 86400
  local thursday_date = os.date("*t", thursday)
  return math.floor((thursday_date.yday - 1) / 7) + 1
end

handlers["YYYY"] = function(d)
  return string.format("%04d", d.year)
end
handlers["YY"] = function(d)
  return string.format("%02d", d.year % 100)
end

handlers["MMMM"] = function(d)
  return MONTHS[d.month]
end
handlers["MMM"] = function(d)
  return MONTHS_SHORT[d.month]
end
handlers["MM"] = function(d)
  return string.format("%02d", d.month)
end
handlers["M"] = function(d)
  return d.month
end

handlers["DD"] = function(d)
  return string.format("%02d", d.day)
end
handlers["D"] = function(d)
  return d.day
end
handlers["Do"] = function(d)
  return tostring(d.day) .. ordinal_suffix(d.day)
end
handlers["DDD"] = function(d)
  return d.yday
end
handlers["DDDD"] = function(d)
  return string.format("%03d", d.yday)
end

handlers["HH"] = function(d)
  return string.format("%02d", d.hour)
end
handlers["H"] = function(d)
  return d.hour
end

handlers["hh"] = function(d)
  local h = d.hour % 12
  if h == 0 then
    h = 12
  end
  return string.format("%02d", h)
end

handlers["h"] = function(d)
  local h = d.hour % 12
  if h == 0 then
    h = 12
  end
  return h
end

handlers["mm"] = function(d)
  return string.format("%02d", d.min)
end
handlers["m"] = function(d)
  return d.min
end

handlers["ss"] = function(d)
  return string.format("%02d", d.sec)
end
handlers["s"] = function(d)
  return d.sec
end

handlers["A"] = function(d)
  return d.hour < 12 and "AM" or "PM"
end
handlers["a"] = function(d)
  return d.hour < 12 and "am" or "pm"
end

handlers["dddd"] = function(d)
  return WEEKDAYS[d.wday]
end
handlers["ddd"] = function(d)
  return WEEKDAYS_SHORT[d.wday]
end
handlers["dd"] = function(d)
  return string.sub(WEEKDAYS_SHORT[d.wday], 1, 2)
end
handlers["d"] = function(d)
  return d.wday - 1
end
handlers["E"] = function(d)
  return iso_weekday(d.wday)
end
handlers["w"] = function(d)
  return week_of_year(d)
end
handlers["ww"] = function(d)
  return string.format("%02d", week_of_year(d))
end
handlers["W"] = function(d, time)
  return iso_week(d, time)
end
handlers["WW"] = function(d, time)
  return string.format("%02d", iso_week(d, time))
end
handlers["Q"] = function(d)
  return math.floor((d.month - 1) / 3) + 1
end

-- --------------------------------------------------
-- LPeg grammar
-- --------------------------------------------------

-- local function token(name)
--   return P(name) / name
-- end

local function token(name)
  return P(name) / function()
    return { type = "token", value = name }
  end
end

-- Order matters (longest first!)
local token_pattern = token "YYYY"
  + token "MMMM"
  + token "dddd"
  + token "DDDD"
  + token "MMM"
  + token "ddd"
  + token "DDD"
  + token "YY"
  + token "MM"
  + token "DD"
  + token "Do"
  + token "HH"
  + token "hh"
  + token "WW"
  + token "ww"
  + token "mm"
  + token "ss"
  + token "dd"
  + token "M"
  + token "D"
  + token "H"
  + token "h"
  + token "m"
  + token "s"
  + token "W"
  + token "w"
  + token "A"
  + token "a"
  + token "d"
  + token "E"
  + token "Q"
  -- localized
  + token "LLLL"
  + token "LLL"
  + token "LL"
  + token "LTS"
  + token "LT"
  + token "L"

---@diagnostic disable-next-line: param-type-mismatch
local literal = P "[" * C((1 - P "]") ^ 0) * P "]" / function(s)
  return { type = "literal", value = s }
end

-- Any other character
local text = C(1) / function(s)
  return { type = "text", value = s }
end

local grammar = Ct((literal + token_pattern + text) ^ 0)

local LONG_DATE_FORMAT = {
  L = "MM/DD/YYYY",
  LL = "MMMM D, YYYY",
  LLL = "MMMM D, YYYY h:mm A", -- TODO: locle support
  LLLL = "dddd, MMMM D, YYYY h:mm A",
  LT = "h:mm A",
  LTS = "h:mm:ss A",
}

local function expand_localized(ast)
  local out = {}

  for _, node in ipairs(ast) do
    if node.type == "token" and LONG_DATE_FORMAT[node.value] then
      -- Parse the expanded format recursively
      local expanded = grammar:match(LONG_DATE_FORMAT[node.value])
      for _, e in ipairs(expanded) do
        out[#out + 1] = e
      end
    else
      out[#out + 1] = node
    end
  end

  return out
end

-- --------------------------------------------------
-- Formatter
-- --------------------------------------------------

local M = {}

function M.format(time, fmt)
  local date = os.date("*t", time)
  local ast = grammar:match(fmt)

  ast = expand_localized(ast)

  local out = {}

  for _, node in ipairs(ast) do
    if node.type == "token" then
      out[#out + 1] = tostring(handlers[node.value](date, time))
    else
      out[#out + 1] = node.value
    end
  end

  return table.concat(out)
end

return M
