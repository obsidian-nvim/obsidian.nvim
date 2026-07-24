---@class obsidian.lsp.CodeActionData
---@field title string|fun(note: obsidian.Note): string
---@field cond fun(note: obsidian.Note): boolean

---@class obsidian.lsp.CodeAction : lsp.CodeAction
---@field data obsidian.lsp.CodeActionData

local log = require "obsidian.log"

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

---@param path string
---@return boolean
local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:match "^%a:[/\\]" ~= nil
end

---@return string?
local function resolve_cursor_attachment()
  local api = require "obsidian.api"
  local util = require "obsidian.util"

  local link = api.cursor_link()
  if not link then
    return nil
  end

  local parsed_location = util.parse_link(link)
  if not parsed_location then
    return nil
  end

  local location = parsed_location
  local decoded = vim.uri_decode(location)
  if decoded then
    location = decoded
  end
  if vim.startswith(location, "file:/") then
    return vim.uri_to_fname(location)
  end

  if is_absolute(location) and vim.fn.filereadable(location) == 1 then
    return location
  end

  local vault_path = tostring(Obsidian.dir / location)
  if vim.fn.filereadable(vault_path) == 1 then
    return vault_path
  end

  return api.resolve_attachment_path(location)
end

local function has_extractable_attachment()
  local path = resolve_cursor_attachment()
  print(path)
  if not path then
    return false
  end
  return require("obsidian.extract").can_extract(path)
end

local function extract_attachment_text()
  local path = resolve_cursor_attachment()
  if not path then
    return log.warn "No attachment link found under cursor"
  end

  local extract = require "obsidian.extract"
  local ok, reason = extract.can_extract(path)
  if not ok then
    return log.warn("Cannot extract text from '%s': %s", path, reason)
  end

  log.info("Extracting text from '%s'", path)
  extract.extract(path, function(err, result)
    if err then
      return log.err("Failed to extract text from '%s': %s", path, err)
    end
    assert(result, "missing extraction result")
    vim.fn.setreg('"', result.text)
    log.info 'Extracted text saved to register "'
  end)
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

  extract_attachment_text = {
    title = "Extract attachment text under cursor",
    cond = has_extractable_attachment,
    fn = extract_attachment_text,
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
