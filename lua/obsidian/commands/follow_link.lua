local api = require "obsidian.api"

---@param data CommandArgs
return function(_, data)
  local opts = {}
  if data.args and string.len(data.args) > 0 then
    opts.open_strategy = data.args
  end

  api.follow_link(nil, opts)
end
