local log = require "obsidian.log"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  -- local offset_days = 0
  -- local arg = string.gsub(data.args, " ", "")
  -- if string.len(arg) > 0 then
  --   local offset = tonumber(arg)
  --   if offset == nil then
  --     log.err "Invalid argument, expected an integer offset"
  --     return
  --   else
  --     offset_days = offset
  --   end
  -- end
  local note = require("obsidian.daily").today()
  client:open_note(note)
end
