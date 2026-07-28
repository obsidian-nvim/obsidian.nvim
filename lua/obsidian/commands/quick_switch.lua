local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  picker.find_notes {
    prompt_title = "Quick Switch",
    query = data.args ~= "" and data.args or nil,
  }
end
