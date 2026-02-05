local log = require "obsidian.log"

return function(data)
  local query = data.args

  local dir = Obsidian.workspaces[#Obsidian.workspaces].path

  if not dir then
    log.err "Failed to locate docs dir"
    return
  end

  Obsidian.picker.find_notes {
    prompt_title = "Help",
    dir = dir,
    query = query,
  }
end
