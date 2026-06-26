local util = require "obsidian.util"
local api = require "obsidian.api"
local cache = require "obsidian.cache"
local log = require "obsidian.log"
local PickerName = require("obsidian.config").Picker
local Mappings = require "obsidian.picker.mappings"

---@class obsidian.Picker
---@field find_files fun(opts: obsidian.PickerFindOpts|?)
---@field grep fun(opts: obsidian.PickerGrepOpts|?)
---@field pick fun(values: obsidian.PickerEntry[]|string[], opts: obsidian.PickerPickOpts|?)
local M = {}

local state = {}
M.state = state

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
---@field no_default_mappings boolean|?
---@field query string|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?
---@field include_non_markdown boolean|?

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(entry: obsidian.PickerEntry)|?
---@field no_default_mappings boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?

---@alias obsidian.PickerEntry vim.quickfix.entry

---@class obsidian.PickerPickOpts
---
---@field prompt_title string|?
---@field callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?
---@field allow_multiple boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?
---@field format_item (fun(value: obsidian.PickerEntry): string)|?
---@field query string|?

------------------------------------------------------------------
--- Concrete methods with a default implementation subclasses. ---
------------------------------------------------------------------

---@param opts obsidian.PickerFindOpts|?
---@return boolean handled
M.find_files_from_cache = function(opts)
  opts = opts or {}
  if not cache.is_enabled() or opts.include_non_markdown then
    return false
  end

  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or vim.fs.normalize(tostring(Obsidian.dir))
  if not util.is_subpath(dir, tostring(Obsidian.dir)) then
    return false
  end

  cache.when_ready(function()
    ---@type obsidian.PickerEntry[]
    local entries = {}
    for path, note in pairs(cache.notes.all()) do
      if util.is_subpath(path, dir) then
        local rel_path = cache.notes.rel_path(path)
        entries[#entries + 1] = {
          display = rel_path,
          ordinal = rel_path,
          filename = path,
          lnum = 1,
          col = 0,
        }
        for _, alias in ipairs(note.aliases or {}) do
          local display = rel_path .. " | " .. alias
          entries[#entries + 1] = {
            display = display,
            ordinal = rel_path .. " " .. alias,
            filename = path,
            lnum = 1,
            col = 0,
          }
        end
      end
    end

    table.sort(entries, function(a, b)
      return (a.display or "") < (b.display or "")
    end)

    M.pick(entries, {
      prompt_title = opts.prompt_title,
      query = opts.query,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      format_item = function(item)
        return item.display or item.filename or ""
      end,
      callback = function(item)
        local path = item.filename
        if not path then
          return
        elseif opts.callback then
          opts.callback(path)
        else
          api.open_note(path)
        end
      end,
    })
  end)

  return true
end

--- Find notes by filename.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(path: string)|?, no_default_mappings: boolean|?, dir: obsidian.Path|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected note path.
---  `no_default_mappings`: Don't apply picker's default mappings.
M.find_notes = function(opts)
  state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = M._note_query_mappings()
    selection_mappings = M._note_selection_mappings()
  end

  -- TODO: build cmd here instead of in all pickers

  return M.find_files {
    query = opts.query,
    prompt_title = opts.prompt_title or "Notes",
    dir = opts.dir or Obsidian.dir,
    callback = opts.callback,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
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

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = M._note_query_mappings()
    selection_mappings = M._note_selection_mappings()
  end

  M.grep {
    prompt_title = opts.prompt_title or "Grep notes",
    dir = opts.dir or Obsidian.dir,
    query = opts.query,
    callback = opts.callback or api.open_note,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
  }
end

--------------------------------
--- Concrete helper methods. ---
--------------------------------

---@param key string|?
---@return boolean
local function key_is_set(key)
  if key ~= nil and string.len(key) > 0 then
    return true
  else
    return false
  end
end

--- Get query mappings to use for `find_notes()` or `grep_notes()`.
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

--- Get selection mappings to use for `find_notes()` or `grep_notes()`.
---@return obsidian.PickerMappingTable
M._note_selection_mappings = function()
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if key_is_set(Obsidian.opts.picker.note_mappings.insert_link) then
    mappings[Obsidian.opts.picker.note_mappings.insert_link] = {
      desc = "insert link",
      callback = Mappings.insert_link,
    }
  end

  return mappings
end

--- Get selection mappings to use for `pick_tag()`.
---@return obsidian.PickerMappingTable
M._tag_selection_mappings = function()
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if key_is_set(Obsidian.opts.picker.tag_mappings.tag_note) then
    mappings[Obsidian.opts.picker.tag_mappings.tag_note] = {
      desc = "tag note",
      callback = Mappings.tag_note,
      fallback_to_query = true,
      keep_open = true,
      allow_multiple = true,
    }
  end

  if key_is_set(Obsidian.opts.picker.tag_mappings.insert_tag) then
    mappings[Obsidian.opts.picker.tag_mappings.insert_tag] = {
      desc = "insert tag",
      callback = Mappings.insert_tag,
      fallback_to_query = true,
    }
  end

  return mappings
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
    patch "obsidian.picker._default"
    return M
  end

  if picker_name then
    picker_name = string.lower(picker_name)
    if not picker_available(picker_name) then
      log.warn_once('Configured picker "%s" is not available; falling back to native picker', picker_name)
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
    patch "obsidian.picker._default"
  end
  return M
end

return M
