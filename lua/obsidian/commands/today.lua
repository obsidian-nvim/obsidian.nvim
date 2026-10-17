local log = require "obsidian.log"
local date_util = require "obsidian.date"

---@param data obsidian.CommandArgs
return function(data)
  local daily = require "obsidian.daily"
  log.info_once "Daily commands today/tomorrow/yesterday are deprecated; use :Obsidian daily. See :Obsidian help Breaking-Changes (Daily notes command redesign)."
  local arg = string.gsub(data.args, " ", "")
  local note

  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset ~= nil then -- It's a numeric offset
      ---@diagnostic disable-next-line: param-type-mismatch
      note = require("obsidian.daily").daily { offset = offset }
    else -- Try parsing as a formatted date
      local date, err = date_util.parse(arg)
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
    note = daily.daily {}
  end
  if note ~= nil then
    note:open { write_if_missing = true }
  end
end
