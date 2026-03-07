return function()
  local note = require("obsidian.actions").new_unique_note()
  note:open { sync = true }
end
