local log = require "obsidian.log"
local util = require "obsidian.util"

---@param data obsidian.CommandArgs
return function(data)
  local offset_days = 0
  local arg = string.gsub(data.args, " ", "")

  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset ~= nil then
      -- It's a numeric offset
      offset_days = offset
    else
      -- Try parsing as a formatted date
      local timestamp, err = util.parse_date(arg)
      if timestamp then
        -- Calculate offset relative to today
        local today_start = os.time {
          year = os.date("*t").year,
          month = os.date("*t").month,
          day = os.date("*t").day,
          hour = 0,
          min = 0,
          sec = 0,
        }
        local target_date = os.date("*t", timestamp)
        local target_start = os.time {
          year = target_date.year,
          month = target_date.month,
          day = target_date.day,
          hour = 0,
          min = 0,
          sec = 0,
        }
        offset_days = math.floor((target_start - today_start) / 86400)
      else
        log.err(string.format("Invalid argument: %s (expected integer offset or date in format like YYYY-MM-DD)", arg))
        return
      end
    end
  end
  local note = require("obsidian.daily").daily(offset_days, {})
  note:open()
end
