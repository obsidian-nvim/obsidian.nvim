local resolvers = require "obsidian.resolvers"
local daily = require "obsidian.daily"

local M = {}

---@param options { offset_start: integer, offset_end:  integer }
---@param callback fun(note: obsidian.Note)
M.open = function(options, callback)
  resolvers.resolve("date_select", {
    intent = "open_daily",
    cadence = "daily",
    offset_start = options.offset_start,
    offset_end = options.offset_end,
  }, function(result)
    if not result or not result.timestamp then
      return
    end
    callback(daily.new_daily_note { date = result.timestamp })
  end)
end

return M
