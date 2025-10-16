local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local offset_quarters = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_quarters = offset
    end
  end
  local note = require("obsidian.quarterly").quarterly(offset_quarters, {})
  note:open()
end
