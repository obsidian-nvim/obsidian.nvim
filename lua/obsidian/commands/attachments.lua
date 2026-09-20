local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  picker.find_attachments {
    prompt_title = "Attachments",
    query = data.args ~= "" and data.args or nil,
  }
end
