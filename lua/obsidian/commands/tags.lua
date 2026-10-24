---@param data obsidian.commands.Args
return function(data)
  local tags = data.fargs or {}
  require("obsidian.actions").search_tags(tags)
end
