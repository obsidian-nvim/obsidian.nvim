local M = {}

--- Format a timestamp with strftime or moment.js date format.
---@param time integer
---@param fmt string
---@param start_of_week? integer First day of the week for Moment-style week tokens (0 is Sunday).
---@return string
M.format = function(time, fmt, start_of_week)
  if fmt:find "%%" then
    local time_string = os.date(fmt, time)
    ---@cast time_string string
    return time_string
  end
  return require("obsidian.lib.moment").format(time, fmt, start_of_week)
end

--- Parse a date with an explicit Moment-style format, or try the common formats.
---@param str string
---@param fmt? string
---@return std.osdate? date
---@return string? error
M.parse = function(str, fmt)
  local parse = require("obsidian.lib.moment").parse
  if fmt ~= nil then
    return parse(str, fmt)
  end

  for _, candidate in ipairs {
    "YYYY-M-D",
    "M/D/YYYY",
    "D/M/YYYY",
    "MMMM D, YYYY",
    "MMM D, YYYY",
    "M-D",
    "M/D",
  } do
    local parsed = parse(str, candidate)
    if parsed then
      return parsed
    end
  end
end

---@param time integer
---@return boolean
M.is_working_day = function(time)
  local weekday = os.date("%w", time)
  return weekday ~= "6" and weekday ~= "0"
end

---@param time integer
---@return integer
M.previous_day = function(time)
  return time - (24 * 60 * 60)
end

---@param time integer
---@return integer
M.next_day = function(time)
  return time + (24 * 60 * 60)
end

---@param time integer
---@return integer
M.working_day_before = function(time)
  local previous = M.previous_day(time)
  if M.is_working_day(previous) then
    return previous
  end
  return M.working_day_before(previous)
end

---@param time integer
---@return integer
M.working_day_after = function(time)
  local next = M.next_day(time)
  if M.is_working_day(next) then
    return next
  end
  return M.working_day_after(next)
end

---@alias datetime_cadence "daily"

--- Resolve a partial relative-date macro such as `@tom`.
---@param macro string
---@return { macro: string, offset: integer, cadence: datetime_cadence }[]
M.resolve_macro = function(macro)
  ---@type { macro: string, offset: integer, cadence: datetime_cadence }[]
  local out = {}
  for name, offset in pairs { today = 0, tomorrow = 1, yesterday = -1 } do
    name = "@" .. name
    if vim.startswith(name, macro) then
      out[#out + 1] = { macro = name, offset = offset, cadence = "daily" }
    end
  end
  return out
end

return M
