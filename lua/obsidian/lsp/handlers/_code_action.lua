---@type table<string, lsp.CodeAction>
local code_actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string  internal server command name, recommend to keep to snake case
---@field title string text display in code action interface
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
      -- TODO: preview?
    },
  }
  code_actions[opts.name] = action
end

---@enum (key) obsidian.lsp.CodeAtionDefaults
local default_actions = {
  rename = {
    name = "obsidian-ls.rename",
    title = "Rename current note",
  },

  add_property = {
    name = "obsidian-ls.add_property",
    title = "Add file property",
  },

  link = {
    name = "obsidian-ls.link",
    title = "Link selection as name for a existing note",
    range = true,
  },

  link_new = {
    name = "obsidian-ls.link_new",
    title = "Link selection as name for a new note",
    range = true,
  },

  extract_note = {
    name = "obsidian-ls.extract_note",
    title = "Extract selected text to a new note",
    range = true,
  },
}

if Obsidian.opts.templates.enabled then
  default_actions.insert_template = {
    name = "obsidian-ls.insert_template",
    title = "Insert template at cursor",
  }
end

-- if Obsidian.opts.slides.enabled then
--   default_actions.start_presentation = {
--     name = "obsidian-ls.start_presentation",
--     title = "Start presentation",
--   }
-- end

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
