local log = require "obsidian.log"
local picker = require "obsidian.picker"

return function(data)
  local query = data.args
  local dir = Obsidian.workspaces[#Obsidian.workspaces].path

  if not dir then
    log.err "Failed to locate docs dir"
    return
  end

  picker.grep {
    prompt_title = "Quick Switch",
    dir = dir,
    query = query,
  }
end
