local commands = {}

---@type lsp.CodeAction[]
local actions = {}

---Register a new command.
---@param name string
---@param config table
local register = function(name, config)
  local mod = require("obsidian.actions")[name]
  actions[#actions + 1] = {
    title = config.title,
    command = {
      title = config.title,
      command = name,
      -- TODO: kind
    },
    data = {
      range = config.range,
      func = mod,
      -- TODO: preview edit
    },
  }
  commands[#commands + 1] = name
end

-- TODO: merge a note to this note, after https://github.com/obsidian-nvim/obsidian.nvim/issues/655

register("rename", {
  title = "Rename current note",
})

register("insert_template", {
  title = "Insert template at curosr",
})

register("add_property", {
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
