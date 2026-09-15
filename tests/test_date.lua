local date = require "obsidian.date"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["format supports Moment-style formats"] = function()
  local timestamp = os.time { year = 2025, month = 4, day = 27, hour = 12 }
  eq("2025-04-27", date.format(timestamp, "YYYY-MM-DD"))
end

T["parse tries common formats"] = function()
  local parsed = assert(date.parse "2025-04-27")
  eq(2025, parsed.year)
  eq(4, parsed.month)
  eq(27, parsed.day)
end

T["previous_day"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(date.previous_day(now), os.time { year = 2025, month = 4, day = 26 })
end

T["next_day"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(date.next_day(now), os.time { year = 2025, month = 4, day = 28 })
end

T["working_day_before"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(date.working_day_before(now), os.time { year = 2025, month = 4, day = 25 })
end

T["working_day_after"] = function()
  local now = os.time { year = 2025, month = 4, day = 25 }
  eq(date.working_day_after(now), os.time { year = 2025, month = 4, day = 28 })
end

T["resolve_macro completes relative dates"] = function()
  local matches = date.resolve_macro "@tom"
  eq(1, #matches)
  eq("@tomorrow", matches[1].macro)
  eq(1, matches[1].offset)
end

return T
