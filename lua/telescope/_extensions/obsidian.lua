local picker = require "obsidian.picker.telescope"

---@diagnostic disable-next-line: undefined-field
return require("telescope").register_extension {
  exports = {
    find_files = picker.workspace_files,
    grep = picker.workspace_grep,
  },
}
