--- Handle the "daily" action.
---@param parsed obsidian.uri.Parsed
local function handle_daily(parsed)
  local daily = require "obsidian.daily"
  local note = daily.today()
  note:open { sync = true }
end

return handle_daily
