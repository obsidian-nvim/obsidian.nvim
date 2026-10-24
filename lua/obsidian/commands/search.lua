local picker = require "obsidian.picker"

---@param data obsidian.commands.Args
return function(data)
  picker.grep_notes {
    query = data.args,
  }
end
