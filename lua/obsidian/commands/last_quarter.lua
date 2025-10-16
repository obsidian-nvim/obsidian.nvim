return function()
  local note = require("obsidian.quarterly").last_quarter()
  note:open()
end
