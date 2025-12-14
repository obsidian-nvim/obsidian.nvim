local api = require "obsidian.api"
local log = require "obsidian.log"
local Path = require "obsidian.path"

return function(data)
  local query = data.args
  local info = api.get_plugin_info "obsidian.nvim"
  if not info then
    log.err "Failed to locate plugin installation directory"
    return
  end

  local dir = Path.new(info.path) / "obsidian.nvim.wiki"

  Obsidian.picker.grep {
    prompt_title = "Quick Switch",
    dir = dir,
    query = query,
  }
end
