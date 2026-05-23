return function()
  local note = require("obsidian.daily").yesterday()
  if not note:exists() then
    note:write()
  end
  note:open()
end
