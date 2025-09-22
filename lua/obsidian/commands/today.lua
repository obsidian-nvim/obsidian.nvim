local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local offset_days = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_days = offset
    end
  end
  local note = require("obsidian.daily").daily(offset_days, {})
  note:open()
end
