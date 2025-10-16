return function()
  local note = require("obsidian.monthly").next_month()
  note:open()
end
