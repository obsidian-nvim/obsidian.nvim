local actions = require "obsidian.actions"

---@param data obsidian.CommandArgs
return function(data)
  local id = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]
  actions.new_from_template(id, template)
end
