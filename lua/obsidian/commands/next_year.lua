return function()
  local note = require("obsidian.yearly").next_year()
  note:open()
end
