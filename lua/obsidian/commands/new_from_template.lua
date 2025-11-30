local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  ---@type string?
  local title = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]
  api.new_from_template(title, template)
end
