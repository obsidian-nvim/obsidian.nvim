local date = require "obsidian.date"
local daily = require "obsidian.daily"
local log = require "obsidian.log"

return function()
  log.info_once "Daily commands today/tomorrow/yesterday are deprecated; use :Obsidian daily. See :Obsidian help Breaking-Changes (Daily notes command redesign)."

  local now = os.time()
  local yesterday
  if Obsidian.opts.daily_notes.workdays_only then
    yesterday = date.working_day_before(now)
  else
    yesterday = date.previous_day(now)
  end

  local note = daily.new_daily_note { date = yesterday }
  if not note:exists() then
    note:write()
  end
  note:open()
end
