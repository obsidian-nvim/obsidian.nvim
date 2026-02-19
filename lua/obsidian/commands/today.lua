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
      local date, err = util.parse_date(arg)
      if date then
        -- Calculate offset relative to today
        local today_start = os.time {
          year = os.date("*t").year,
          month = os.date("*t").month,
          day = os.date("*t").day,
          hour = 0,
          min = 0,
          sec = 0,
        }
        local target_start =
          os.time { year = date.year, month = date.month, day = date.day, hour = 0, min = 0, sec = 0 }
        offset_days = math.floor((target_start - today_start) / 86400)
      else
        log.err(
          string.format(
            "Invalid argument: %s (expected integer offset or date in format like YYYY-MM-DD)\nErr: %s",
            arg,
            err
          )
        )
        return
      end
    end
  end
  -- TODO: no need to have offset_days if we can just pass the date directly to daily() and let it handle formatting and path generation
  local note = require("obsidian.daily").daily(offset_days, {})
  note:open()
end
