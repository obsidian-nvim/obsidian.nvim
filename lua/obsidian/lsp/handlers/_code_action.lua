---@alias obsidian.lsp.CodeAtionDefaults
---| "rename"
---| "insert_template"
---| "add_property"
---| "link"
---| "link_new"
---| "extract_note"

---@type table<string, lsp.CodeAction>
local actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string | obsidian.lsp.CodeAtionDefaults internal server command name, recommend to keep to snake case
---@field title string text display in code action interface
---@field fn function|? function to run
---@field range boolean|? whether to show action only in visual mode

---Register a new command.
---@param config obsidian.lsp.CodeActionOpts
local add = function(config)
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
  actions[config.name] = action
end

-- TODO: merge a note to this note, after https://github.com/obsidian-nvim/obsidian.nvim/issues/655

add {
  name = "rename",
  title = "Rename current note",
}

add {
  name = "insert_template",
  title = "Insert template at cursor",
}

add {
  name = "add_property",
  title = "Add file property",
}

add {
  name = "link",
  title = "Link selection as name for a existing note",
  range = true,
}

add {
  name = "link_new",
  title = "Link selection as name for a new note",
  range = true,
}

add {
  name = "extract_note",
  title = "Extract selected text to a new note",
  range = true,
}

---@param name string | obsidian.lsp.CodeAtionDefaults
local del = function(name)
  actions[name] = nil
end

return {
  actions = actions,
  add = add,
  del = del,
}
