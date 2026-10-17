local resolvers = require "obsidian.resolvers"
local daily = require "obsidian.daily"

local M = {}

---@param offset_start integer
---@param offset_end integer
---@param callback fun(note: obsidian.Note)
M.open = function(offset_start, offset_end, callback)
  resolvers.resolve("date_select", {
    intent = "open_daily",
    cadence = "daily",
    offset_start = offset_start,
    offset_end = offset_end,
  }, function(result)
    if not result or not result.timestamp then
      return
    end
    callback(daily.new_daily_note { date = result.timestamp })
  end)
end
