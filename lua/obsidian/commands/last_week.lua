return function()
  local note = require("obsidian.weekly").last_week()
  note:open()
end
