local api = require "obsidian.api"
local PickerName = require("obsidian.config").Picker

---@class obsidian.Picker
---@field find_files fun(opts: obsidian.PickerFindOpts|?)
---@field grep fun(opts: obsidian.PickerGrepOpts|?)
---@field pick fun(values: obsidian.PickerEntry[]|string[], opts: obsidian.PickerPickOpts|?)
local M = {}

local state = {}
M.state = state

-------------------------------------------------------------------
--- Abstract methods that need to be implemented by subclasses. ---
-------------------------------------------------------------------

---@class obsidian.PickerMappingOpts
---
---@field desc string
---@field callback fun(...: obsidian.PickerEntry|string)
---@field fallback_to_query boolean|?
---@field keep_open boolean|?
---@field allow_multiple boolean|?

---@alias obsidian.PickerMappingTable table<string, obsidian.PickerMappingOpts>

---@class obsidian.PickerFindOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field callback fun(path: string)|?
---@field query string|?

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(entry: obsidian.PickerEntry)|?

---@class obsidian.PickerEntry: vim.quickfix.entry

---@class obsidian.PickerPickOpts
---
---@field prompt_title string|?
---@field callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?
---@field allow_multiple boolean|?
---@field format_item (fun(value: obsidian.PickerEntry): string)|?

------------------------------------------------------------------
--- Concrete methods with a default implementation subclasses. ---
------------------------------------------------------------------

--- Find notes by filename.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(path: string)|?, dir: obsidian.Path|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected note path.
---  `no_default_mappings`: Don't apply picker's default mappings.
M.find_notes = function(opts)
  state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  state.class = M.find_files {
    query = opts.query,
    prompt_title = opts.prompt_title or "Notes",
    dir = opts.dir or Obsidian.dir,
    callback = opts.callback,
  }
end

--- Grep search in notes.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(entry: obsidian.PickerEntry)|?, no_default_mappings: boolean|?, dir: obsidian.Path|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `query`: Initial query to grep for.
---  `callback`: Callback to run with the selected path.
---  `no_default_mappings`: Don't apply picker's default mappings.
M.grep_notes = function(opts)
  state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  M.grep {
    prompt_title = opts.prompt_title or "Grep notes",
    dir = opts.dir or Obsidian.dir,
    query = opts.query,
    callback = opts.callback or api.open_note,
  }
end

--- Open picker with a list of notes.
---
---@param notes obsidian.Note[]
---@param opts { prompt_title: string|?, callback: fun(note: obsidian.Note, ...: obsidian.Note), allow_multiple: boolean|?, no_default_mappings: boolean|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected note(s).
---  `allow_multiple`: Allow multiple selections to pass to the callback.
M.pick_note = function(notes, opts)
  state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  -- Launch picker with results.
  ---@type obsidian.PickerEntry[]
  local entries = {}
  for _, note in ipairs(notes) do
    assert(note.path, "note has no path")
    local rel_path = assert(note.path:vault_relative_path { strict = true })
    local display_name = note:display_name()
    entries[#entries + 1] = {
      value = note,
      display = display_name,
      ordinal = rel_path .. " " .. display_name,
      filename = tostring(note.path),
    }
  end

  M.pick(entries, {
    prompt_title = opts.prompt_title or "Notes",
    callback = function(v)
      opts.callback(v.user_data)
    end,
    allow_multiple = opts.allow_multiple,
  })
end

-- ---@param key string|?
-- ---@return boolean
-- local function key_is_set(key)
--   if key ~= nil and string.len(key) > 0 then
--     return true
--   else
--     return false
--   end
-- end

-- --- Get selection mappings to use for `pick_tag()`.
-- ---@return obsidian.PickerMappingTable
-- M._tag_selection_mappings = function()
--   ---@type obsidian.PickerMappingTable
--   local mappings = {}
--
--   if key_is_set(Obsidian.opts.picker.tag_mappings.tag_note) then
--     mappings[Obsidian.opts.picker.tag_mappings.tag_note] = {
--       desc = "tag note",
--       callback = Mappings.tag_note,
--       fallback_to_query = true,
--       keep_open = true,
--       allow_multiple = true,
--     }
--   end
--
--   if key_is_set(Obsidian.opts.picker.tag_mappings.insert_tag) then
--     mappings[Obsidian.opts.picker.tag_mappings.insert_tag] = {
--       desc = "insert tag",
--       callback = Mappings.insert_tag,
--       fallback_to_query = true,
--     }
--   end
--
--   return mappings
-- end

--- Get the default Picker.
---
---@param picker_name obsidian.config.Picker|?
M.get = function(picker_name)
  picker_name = picker_name and picker_name or Obsidian.opts.picker.name

  local patch = function(modname)
    for name, f in pairs(require(modname)) do
      M[name] = f
    end
  end

  if picker_name then
    picker_name = string.lower(picker_name)
  elseif picker_name == false then
    patch "obsidian.picker._default"
    M.state._native = true
    return M
  else
    for _, name in ipairs { PickerName.telescope, PickerName.fzf_lua, PickerName.mini, PickerName.snacks } do
      local ok = pcall(M.get, name)
      if ok then
        return M
      end
    end
  end

  if picker_name == string.lower(PickerName.telescope) then
    patch "obsidian.picker._telescope"
  elseif picker_name == string.lower(PickerName.mini) then
    patch "obsidian.picker._mini"
  elseif picker_name == string.lower(PickerName.fzf_lua) then
    patch "obsidian.picker._fzf"
  elseif picker_name == string.lower(PickerName.snacks) then
    patch "obsidian.picker._snacks"
  else
    patch "obsidian.picker._default"
  end
  return M
end

return M
