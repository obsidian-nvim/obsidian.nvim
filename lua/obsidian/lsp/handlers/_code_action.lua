---@type table<string, lsp.CodeAction>
local code_actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string unique name
---@field title string text display in code action interface
---@field cond? fun(note: obsidian.Note): boolean function used to determine whether code actoin is shown
---@field fn? function

---Register a new command.
---@param opts obsidian.lsp.CodeActionOpts
local add = function(opts)
  -- TODO: validate
  local action = {
    title = opts.title,
    command = {
      title = opts.title,
      command = "obsidian." .. opts.name,
      -- TODO: kind
    },
    data = {
      cond = opts.cond or function()
        return true
      end,
      -- TODO: preview?
    },
  }

  if opts.fn then
    vim.lsp.commands["obsidian." .. opts.name] = vim.schedule_wrap(function(params)
      opts.fn(unpack(params.arguments or {}))
    end)
  end
  code_actions[opts.name] = action
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

  start_presentation = {
    title = "Start presentation",
    cond = function()
      return Obsidian.opts.slides.enabled
    end,
  },
}

---@param name string
local del = function(name)
  code_actions[name] = nil
end

for name, opts in pairs(default_actions) do
  opts.name = name
  add(opts)
end

return {
  actions = code_actions,
  add = add,
  del = del,
}
