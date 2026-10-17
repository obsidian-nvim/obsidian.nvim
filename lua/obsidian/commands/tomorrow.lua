local date = require "obsidian.date"
local daily = require "obsidian.daily"
local log = require "obsidian.log"

return function()
  log.info_once "Daily commands today/tomorrow/yesterday are deprecated; use :Obsidian daily. See :Obsidian help Breaking-Changes (Daily notes command redesign)."

  local now = os.time()
  local tomorrow
  if Obsidian.opts.daily_notes.workdays_only then
    tomorrow = date.working_day_after(now)
  else
    tomorrow = date.next_day(now)
  end

  daily.daily({ date = tomorrow }):open { write_if_missing = true }
end
