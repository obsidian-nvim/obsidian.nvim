local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  picker.grep_notes {
    query = data.args,
  }
end
