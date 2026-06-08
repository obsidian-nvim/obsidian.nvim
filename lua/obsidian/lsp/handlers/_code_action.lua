---@class obsidian.lsp.CodeActionData
---@field title string|fun(note: obsidian.Note): string
---@field cond fun(note: obsidian.Note): boolean

---@class obsidian.lsp.CodeAction : lsp.CodeAction
---@field data obsidian.lsp.CodeActionData

---@type table<string, obsidian.lsp.CodeAction>
local code_actions = {}

---@class obsidian.lsp.CodeActionOpts
---@field name string unique name
---@field title string|fun(note: obsidian.Note): string text display in code action interface
---@field cond? fun(note: obsidian.Note): boolean function used to determine whether code actoin is shown
---@field fn? function

---Register a new command.
---@param opts obsidian.lsp.CodeActionOpts
local add = function(opts)
  -- TODO: validate
  local title = type(opts.title) == "string" and opts.title or ""
  local action = {
    title = title,
    command = {
      title = title,
      command = "obsidian." .. opts.name,
      -- TODO: kind
    },
    data = {
      title = opts.title,
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
  return (vim.api.nvim_get_mode().mode:find "v") ~= nil
end

local function is_recording_audio()
  return require("obsidian.core-plugins.audio_recorder").is_recording()
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
      return Obsidian.opts.templates.enabled == true
    end,
  },

  start_presentation = {
    title = "Start presentation",
    cond = function()
      return Obsidian.opts.slides.enabled == true
    end,
  },

  add_attachment = {
    title = "Add attachment from folder, filepath or url",
  },

  insert_link = {
    title = "Insert internal link at cursor",
  },

  insert_tag = {
    title = "Insert tag at cursor",
  },

  --- TODO: add_alias
  add_tag = {
    title = "Add tag to frontmatter",
  },

  toggle_recording = {
    title = function()
      return is_recording_audio() and "Stop recording audio" or "Start recording audio as attachment"
    end,
  },

  link_url = {
    title = "Convert URL under cursor to markdown link",
    cond = function()
      return require("obsidian.weblink").url_at_cursor() ~= nil
    end,
  },
}

---@param name string
local del = function(name)
  code_actions[name] = nil
end

for name, opts in pairs(default_actions) do
  ---@type obsidian.lsp.CodeActionOpts
  local action_opts = vim.tbl_extend("force", opts, { name = name })
  add(action_opts)
end

return {
  actions = code_actions,
  add = add,
  del = del,
}
