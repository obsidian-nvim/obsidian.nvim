local actions = require "obsidian.actions"

---@param data obsidian.CommandArgs
return function(data)
  local template_name
  if string.len(data.args) > 0 then
    template_name = vim.trim(data.args)
  end
  actions.insert_template(template_name)
end
