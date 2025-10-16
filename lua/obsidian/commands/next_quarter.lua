return function()
  local note = require("obsidian.quarterly").next_quarter()
  note:open()
end
