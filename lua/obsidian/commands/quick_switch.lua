local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  picker.find_notes {
    prompt_title = "Quick Switch",
    query = data.args ~= "" and data.args or nil,
    show_existing_only = Obsidian.opts.quick_switch.show_existing_only,
    show_attachments = Obsidian.opts.quick_switch.show_attachments,
  }
end
