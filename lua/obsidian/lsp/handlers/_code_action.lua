local commands = {}

---@type lsp.CodeAction[]
local actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string internal server command name, recommend to keep to snake case
---@field title string text display in code action interface
---@field fn function|? function to run
---@field range boolean|? whether to show action only in visual mode

local actions_lookup = {}

---Register a new command.
---@param config obsidian.lsp.CodeActionOpts
local register = function(config)
  local fn = config.fn or require("obsidian.actions")[config.name]
  if not fn then
    -- TODO:
    return
  end
  local action = {
    title = config.title,
    command = {
      title = config.title,
      command = config.name,
      -- TODO: kind
    },
    data = {
      range = config.range,
      fn = fn,
      -- TODO: preview edit
    },
  }
  commands[#commands + 1] = config.name
  actions[#actions + 1] = action
  actions_lookup[config.name] = action
end

-- TODO: merge a note to this note, after https://github.com/obsidian-nvim/obsidian.nvim/issues/655

register {
  name = "rename",
  title = "Rename current note",
}

register {
  name = "insert_template",
  title = "Insert template at curosr",
}

register {
  name = "add_property",
  title = "Add file property",
}

register {
  name = "link",
  title = "Link selection as name for a existing note",
  range = true,
}

register {
  name = "link_new",
  title = "Link selection as name for a new note",
  range = true,
}

register {
  name = "extract_note",
  title = "Extract selected text to a new note",
  range = true,
}

return {
  commands = commands,
  actions = actions,
  actions_lookup = actions_lookup,
  register = register,
}
