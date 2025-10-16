return function()
  local note = require("obsidian.monthly").last_month()
  note:open()
end
