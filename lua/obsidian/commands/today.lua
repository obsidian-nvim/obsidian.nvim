local log = require "obsidian.log"
local util = require "obsidian.util"

---@param data obsidian.CommandArgs
return function(data)
  local arg = string.gsub(data.args, " ", "")
  local note

  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset ~= nil then -- It's a numeric offset
      ---@diagnostic disable-next-line: param-type-mismatch
      note = require("obsidian.daily").daily { offset = offset }
    else -- Try parsing as a formatted date
      local date, err = util.parse_date(arg)
      if date then
        ---@diagnostic disable-next-line: param-type-mismatch
        note = require("obsidian.daily").daily { date = os.time(date) }
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
  else
    note = require("obsidian.daily").today()
  end
  if note ~= nil then
    note:open()
  end
end
