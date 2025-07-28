return function()
  local note = require("obsidian.daily").yesterday()
  note:open()
end
