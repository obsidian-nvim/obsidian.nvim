local api = require "obsidian.api"
local log = require "obsidian.log"
local PickerName = require("obsidian.config").Picker
local Mappings = require "obsidian.picker.mappings"

---@class obsidian.Picker
---@field find_files fun(opts: obsidian.PickerFindOpts|?)
---@field grep fun(opts: obsidian.PickerGrepOpts|?)
---@field pick fun(values: obsidian.PickerEntry[]|string[], opts: obsidian.PickerPickOpts|?)
local M = {}

local supports_query_mappings = false

local picker_plugins = {
  [string.lower(PickerName.telescope)] = { "telescope.nvim" },
  [string.lower(PickerName.fzf_lua)] = { "fzf-lua" },
  [string.lower(PickerName.mini)] = { "mini.nvim", "mini.pick" },
  [string.lower(PickerName.snacks)] = { "snacks.nvim" },
  ["snacks.pick"] = { "snacks.nvim" },
}

---@param picker_name string
---@return boolean
local function picker_available(picker_name)
  local plugins = picker_plugins[string.lower(picker_name)]
  if plugins == nil then
    return false
  end

  for _, plugin in ipairs(plugins) do
    if api.get_plugin_info(plugin) ~= nil then
      return true
    end
  end

  return false
end

-------------------------------------------------------------------
--- Abstract methods that need to be implemented by subclasses. ---
-------------------------------------------------------------------

---@class obsidian.PickerMappingOpts
---
---@field desc string
---@field callback fun(query: string)

---@alias obsidian.PickerMappingTable table<string, obsidian.PickerMappingOpts>

---@class obsidian.PickerFindOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field callback fun(path: string)|?
---@field query string|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field include_non_markdown boolean|?

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(entry: obsidian.PickerEntry)|?
---@field query_mappings obsidian.PickerMappingTable|?

---@class obsidian.PickerEntry: vim.quickfix.entry

---@class obsidian.PickerPickOpts
---
---@field prompt_title string|?
---@field callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?
---@field allow_multiple boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field format_item (fun(value: obsidian.PickerEntry): string)|?

------------------------------------------------------------------
--- Concrete methods with a default implementation subclasses. ---
------------------------------------------------------------------

---@param key string|?
---@return boolean
local function key_is_set(key)
  return key ~= nil and string.len(key) > 0
end

---@param mappings obsidian.PickerMappingTable|?
---@return boolean
local function has_mappings(mappings)
  return mappings ~= nil and next(mappings) ~= nil
end

--- Get query mappings to use for note pickers.
---@return obsidian.PickerMappingTable
M._note_query_mappings = function()
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if key_is_set(Obsidian.opts.picker.note_mappings.new) then
    mappings[Obsidian.opts.picker.note_mappings.new] = {
      desc = "new",
      callback = Mappings.new_note,
    }
  end

  return mappings
end

---@param query_mappings obsidian.PickerMappingTable
local function warn_unsupported_query_mappings(query_mappings)
  if supports_query_mappings or not has_mappings(query_mappings) then
    return
  end
  log.warn_once "picker.note_mappings.new is only supported by telescope.nvim and fzf-lua. With this picker, use action-first commands such as `Obsidian new`, `Obsidian link_new`, or `Obsidian insert_link`; see docs/Actions.md."
end

--- Find notes by filename.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(path: string)|?, no_default_mappings: boolean|?, dir: obsidian.Path|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected note path.
---  `no_default_mappings`: Don't apply default note query mappings.
---  `dir`: the directory full path to search in
M.find_notes = function(opts)
  opts = opts or {}

  local query_mappings
  if not opts.no_default_mappings then
    query_mappings = M._note_query_mappings()
    warn_unsupported_query_mappings(query_mappings)
  end

  M.find_files {
    query = opts.query,
    prompt_title = opts.prompt_title or "Notes",
    dir = opts.dir or Obsidian.dir,
    callback = opts.callback,
    query_mappings = query_mappings,
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
---  `no_default_mappings`: Don't apply default note query mappings.
M.grep_notes = function(opts)
  opts = opts or {}

  local query_mappings
  if not opts.no_default_mappings then
    query_mappings = M._note_query_mappings()
    warn_unsupported_query_mappings(query_mappings)
  end

  M.grep {
    prompt_title = opts.prompt_title or "Grep notes",
    dir = opts.dir or Obsidian.dir,
    query = opts.query,
    callback = opts.callback or api.open_note,
    query_mappings = query_mappings,
  }
end

--- Get the default Picker.
---
---@param picker_name obsidian.config.Picker
M.get = function(picker_name)
  local patch = function(modname)
    for name, f in pairs(require(modname)) do
      M[name] = f
    end
  end

  if picker_name == false then
    supports_query_mappings = false
    patch "obsidian.picker._default"
    return M
  end

  if picker_name then
    picker_name = string.lower(picker_name)
    if not picker_available(picker_name) then
      log.warn_once('Configured picker "%s" is not available; falling back to native picker', picker_name)
      supports_query_mappings = false
      patch "obsidian.picker._default"
      return M
    end
  else
    for _, name in ipairs { PickerName.telescope, PickerName.fzf_lua, PickerName.mini, PickerName.snacks } do
      if picker_available(name) then
        return M.get(name)
      end
    end
  end

  supports_query_mappings = picker_name == string.lower(PickerName.telescope)
    or picker_name == string.lower(PickerName.fzf_lua)

  if picker_name == string.lower(PickerName.telescope) then
    patch "obsidian.picker._telescope"
  elseif picker_name == string.lower(PickerName.mini) then
    patch "obsidian.picker._mini"
  elseif picker_name == string.lower(PickerName.fzf_lua) then
    patch "obsidian.picker._fzf"
    -- or statement added for backwards compatibility
  elseif picker_name == string.lower(PickerName.snacks) or picker_name == "snacks.pick" then
    patch "obsidian.picker._snacks"
  else
    supports_query_mappings = false
    patch "obsidian.picker._default"
  end
  return M
end

return M
