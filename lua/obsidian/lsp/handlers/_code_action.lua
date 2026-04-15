---@type table<string, lsp.CodeAction>
local code_actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field title string text display in code action interface
---@field cond? fun(note: obsidian.Note): boolean function used to determine whether code actoin is shown

---Register a new command.
---@param opts obsidian.lsp.CodeActionOpts
local add = function(name, opts)
  -- TODO: validate
  local action = {
    title = opts.title,
    command = {
      title = opts.title,
      command = "obsidian." .. name,
      -- TODO: kind
    },
    data = {
      cond = opts.cond or function()
        return true
      end,
      -- TODO: preview?
    },
  }
  code_actions[name] = action
end

local function in_visual()
  return vim.api.nvim_get_mode().mode:find "v" ~= nil
end

local default_actions = {
  add_property = {
    title = "Add file property",
  },

  merge_note = {
    title = "Merge current note into another note",
  },

  move_note = {
    title = "Move current note to another folder",
  },

  link = {
    title = "Link selection as name for a existing note",
    cond = in_visual,
  },

  link_new = {
    title = "Link selection as name for a new note",
    cond = in_visual,
  },

  extract_note = {
    title = "Extract selected text to a new note",
    cond = in_visual,
  },

  insert_template = {
    title = "Insert template at cursor",
    cond = function()
      return Obsidian.opts.templates.enabled
    end,
  },
}

-- if Obsidian.opts.slides.enabled then
--   default_actions.start_presentation = {
--     name = "obsidian-ls.start_presentation",
--     title = "Start presentation",
--   }
-- end

---@param name string
local del = function(name)
  code_actions[name] = nil
end

for name, action in pairs(default_actions) do
  add(name, action)
end

return {
  actions = code_actions,
  add = add,
  del = del,
}
