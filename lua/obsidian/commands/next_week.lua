return function()
  local note = require("obsidian.weekly").next_week()
  note:open()
end
