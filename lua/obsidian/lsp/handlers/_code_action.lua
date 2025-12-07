local commands = {}

---@type lsp.CodeAction[]
local actions = {}

---Register a new command.
---@param name string
---@param config table
local register = function(name, config)
  local mod = require("obsidian.lsp.commands." .. name)
  actions[#actions + 1] = {
    title = config.title,
    command = {
      title = config.title,
      command = name,
      -- TODO: kind
    },
    data = {
      range = config.range,
      func = type(mod) == "table" and mod.command or mod,
      edit = type(mod) == "table" and mod.edit or nil,
    },
  }
  commands[#commands + 1] = name
end

register("add_file_property", {
  title = "Add file property",
})

register("link", {
  title = "Link selection as name for a existing note",
  range = true,
})

register("link_new", {
  title = "Link selection as name for a new note",
  range = true,
})

register("extract_note", {
  title = "Extract selected text to a new note",
  range = true,
})

return {
  commands = commands,
  actions = actions,
}
