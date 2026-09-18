return function()
  local note = require("obsidian.daily").tomorrow()
  if not note:exists() then
    note:write()
  end
  note:open()
end
