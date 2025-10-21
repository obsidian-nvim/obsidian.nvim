local api = require "obsidian.api"
local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local opts = {}
  if data.args and string.len(data.args) > 0 then
    opts.open_strategy = data.args
  end

  local link = api.cursor_link()

  if link then
    api.follow_link(link, opts)
  else
    log.info "no valid link to follow"
  end
end
