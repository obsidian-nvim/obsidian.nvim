return function()
  local note = require("obsidian.daily").tomorrow()
  note:open()
end
