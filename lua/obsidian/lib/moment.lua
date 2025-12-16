-- moment_lpeg.lua
local lpeg = vim.lpeg

local P, R, S, C, Ct = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct

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
  + token "MMM"
  + token "ddd"
  + token "YY"
  + token "MM"
  + token "DD"
  + token "HH"
  + token "hh"
  + token "mm"
  + token "ss"
  + token "M"
  + token "D"
  + token "H"
  + token "h"
  + token "m"
  + token "s"
  + token "A"
  + token "a"
  -- localized
  + token "LLLL"
  + token "LLL"
  + token "LL"
  + token "LTS"
  + token "LT"
  + token "L"

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
  LT = "HH:mm",
  LTS = "HH:mm:ss",
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
      out[#out + 1] = tostring(handlers[node.value](date))
    else
      out[#out + 1] = node.value
    end
  end

  return table.concat(out)
end

return M
