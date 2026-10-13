return function()
  local daily = require "obsidian.daily"
  daily.warn_legacy_command()
  daily.open(daily.yesterday())
end
