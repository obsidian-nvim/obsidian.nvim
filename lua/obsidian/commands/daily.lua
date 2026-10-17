local daily = require "obsidian.daily"
local log = require "obsidian.log"
local resolvers = require "obsidian.resolvers"

---@param data obsidian.CommandArgs
return function(data)
  local input = vim.trim(data.args or "")
  if input == "" then
    daily.daily({}):open { write_if_missing = true }
    return
  end

  resolvers.resolve("date_parse", { input = input, intent = "open_daily" }, function(result)
    if not result then
      return
    end
    local timestamp = result.timestamp
    if type(timestamp) ~= "number" or timestamp % 1 ~= 0 then
      log.err "date_parse resolver must return an integer timestamp"
      return
    end
    ---@cast timestamp integer
    daily.daily({ date = timestamp }):open { write_if_missing = true }
  end)
end
