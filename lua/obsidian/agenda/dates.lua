local util = require "obsidian.util"

local M = {}

local SECONDS_PER_DAY = 24 * 60 * 60

---@param t integer
---@return integer
M.start_of_day = function(t)
  local d = os.date("*t", t)
  ---@cast d osdateparam
  d.hour, d.min, d.sec = 12, 0, 0
  return os.time(d)
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
  start_of_week = start_of_week or (Obsidian and Obsidian.opts.date and Obsidian.opts.date.start_of_week) or 1
  t = M.start_of_day(t)
  local weekday = tonumber(os.date("%w", t)) or 0
  local delta = (weekday - start_of_week) % 7
  return M.add_days(t, -delta)
end

---@param t integer
---@return integer
M.start_of_month = function(t)
  local d = os.date("*t", t)
  ---@cast d osdateparam
  d.day, d.hour, d.min, d.sec = 1, 12, 0, 0
  return os.time(d)
end

---@param t integer
---@return integer
M.start_of_year = function(t)
  local d = os.date("*t", t)
  ---@cast d osdateparam
  d.month, d.day, d.hour, d.min, d.sec = 1, 1, 12, 0, 0
  return os.time(d)
end

---@param t integer
---@return integer
M.days_in_month = function(t)
  local d = os.date("*t", t)
  ---@cast d osdateparam
  d.month = d.month + 1
  d.day = 0
  d.hour, d.min, d.sec = 12, 0, 0
  local last = os.time(d)
  return tonumber(os.date("%d", last)) or 31
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
