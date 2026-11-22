local navigation = require "obsidian.navigation"

---@param data obsidian.commands.Args
return function(data)
  local strategy = data.args and vim.trim(data.args) or nil
  ---@cast strategy obsidian.config.OpenStrategy?
  navigation.follow_link(nil, { open_strategy = strategy ~= "" and strategy or nil })
end
