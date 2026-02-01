local actions = require "obsidian.actions"

---@type table<string, lsp.CodeAction>
local code_actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string  internal server command name, recommend to keep to snake case
---@field title string text display in code action interface
---@field fn function function to run
---@field range boolean|? whether to show action only in visual mode

---Register a new command.
---@param opts obsidian.lsp.CodeActionOpts
local add = function(opts)
  -- TODO: validate
  local action = {
    title = opts.title,
    command = {
      title = opts.title,
      command = opts.name,
      -- TODO: kind
    },
    data = {
      range = opts.range,
      fn = opts.fn,
      -- TODO: preview edit with preview_fn
    },
  }
  code_actions[opts.name] = action
end

---@enum (key) obsidian.lsp.CodeAtionDefaults
local default_actions = {
  rename = {
    name = "rename",
    title = "Rename current note",
    fn = actions.rename,
  },

  insert_template = {
    name = "insert_template",
    title = "Insert template at cursor",
    fn = actions.insert_template,
  },

  add_property = {
    name = "add_property",
    title = "Add file property",
    fn = actions.add_property,
  },

  link = {
    name = "link",
    title = "Link selection as name for a existing note",
    fn = actions.link,
    range = true,
  },

  link_new = {
    name = "link_new",
    title = "Link selection as name for a new note",
    fn = actions.link_new,
    range = true,
  },

  extract_note = {
    name = "extract_note",
    title = "Extract selected text to a new note",
    fn = actions.extract_note,
    range = true,
  },
}

-- TODO: merge a note to this note, after https://github.com/obsidian-nvim/obsidian.nvim/issues/655

---@param name string | obsidian.lsp.CodeAtionDefaults
local del = function(name)
  code_actions[name] = nil
end

for _, action in pairs(default_actions) do
  add(action)
end

return {
  actions = code_actions,
  add = add,
  del = del,
}
