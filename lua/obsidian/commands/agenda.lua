local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local agenda = require "obsidian.agenda"
  local ok, view_name, date = pcall(agenda.parse_args, data.fargs)
  if not ok then
    log.err(view_name)
    return
  end
  agenda.open { view = view_name, date = date }
end
