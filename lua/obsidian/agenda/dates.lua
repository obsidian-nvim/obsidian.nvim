local util = require "obsidian.util"

local M = {}

local SECONDS_PER_DAY = 24 * 60 * 60

---@param t integer
---@return integer
M.start_of_day = function(t)
  local d = os.date("*t", t)
  if type(d) ~= "table" then
    return t
  end
  return os.time { year = d.year, month = d.month, day = d.day, hour = 12, min = 0, sec = 0 }
end

---@param t integer
---@param days integer
---@return integer
M.add_days = function(t, days)
  return M.start_of_day(t + (days * SECONDS_PER_DAY))
end

---@param str string
---@return integer?
M.parse = function(str)
  if not str:match "^%d%d%d%d%-%d%d?%-%d%d?$" then
    return nil
  end

  local d = util.parse_date(str, "YYYY-M-D")
  if not d then
    return nil
  end
  d.hour, d.min, d.sec = 12, 0, 0
  return os.time(d)
end

---@param t integer
---@return string
M.format = function(t)
  return util.format_date(t, "YYYY-MM-DD")
end

---@param t integer
---@return string
M.format_day = function(t)
  return util.format_date(t, "ddd YYYY-MM-DD")
end

---@param t integer
---@return string
M.format_month = function(t)
  return util.format_date(t, "MMMM YYYY")
end

---@param t integer
---@return string
M.format_year = function(t)
  return util.format_date(t, "YYYY")
end

---@param t integer
---@return string
M.key = function(t)
  return M.format(t)
end

---@param t integer
---@param start_of_week integer|?
---@return integer
M.start_of_week = function(t, start_of_week)
  local week_start = start_of_week or (Obsidian and Obsidian.opts.date and Obsidian.opts.date.start_of_week) or 1
  t = M.start_of_day(t)
  local weekday = tonumber(os.date("%w", t)) or 0
  local delta = (weekday - week_start) % 7
  return M.add_days(t, -math.floor(delta))
end

---@param t integer
---@return integer
M.start_of_month = function(t)
  local d = os.date("*t", t)
  if type(d) ~= "table" then
    return t
  end
  return os.time { year = d.year, month = d.month, day = 1, hour = 12, min = 0, sec = 0 }
end

---@param t integer
---@return integer
M.start_of_year = function(t)
  local d = os.date("*t", t)
  if type(d) ~= "table" then
    return t
  end
  return os.time { year = d.year, month = 1, day = 1, hour = 12, min = 0, sec = 0 }
end

---@param t integer
---@return integer
M.days_in_month = function(t)
  local d = os.date("*t", t)
  if type(d) ~= "table" then
    return 31
  end
  ---@type integer
  local year = math.floor(tonumber(d.year) or 1970)
  ---@type integer
  local month = math.floor(d.month + 1)
  ---@type std.osdateparam
  local next_month_date = { year = year, month = month, day = 1, hour = 12, min = 0, sec = 0 }
  local next_month = os.time(next_month_date)
  return math.floor(tonumber(os.date("%d", next_month - SECONDS_PER_DAY)) or 31)
end

---@param a integer?
---@param b integer?
---@return boolean
M.same_day = function(a, b)
  if not a or not b then
    return false
  end
  return M.key(a) == M.key(b)
end

return M
