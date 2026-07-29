local util = require "obsidian.util"
local picker_util = require "obsidian.picker.util"
local api = require "obsidian.api"
local icons = require "obsidian.icons"
local log = require "obsidian.log"
local PickerName = require("obsidian.config").Picker
local Mappings = require "obsidian.picker.mappings"
local Path = require "obsidian.path"
local search = require "obsidian.search"

---@class obsidian.Picker
---@field find_files fun(opts: obsidian.PickerFindOpts|?)
---@field grep fun(opts: obsidian.PickerGrepOpts|?)
---@field select fun(items: any[], opts: obsidian.PickerSelectOpts|?, on_choice: fun(choices: any[])|?)
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
---@field callback fun(paths: string[])|?
---@field no_default_mappings boolean|?
---@field query string|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?
---@field include_non_markdown boolean|?
---@field use_cache boolean|?
---@field show_existing_only boolean|?
---@field show_attachments boolean|?

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path
---@field query string|?
---@field callback fun(entries: obsidian.PickerEntry[])|?
---@field no_default_mappings boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?

---@alias obsidian.PickerEntry vim.quickfix.entry

---@alias obsidian.ui_select_preview_spec { buf: integer, pos: [integer,integer]?, pos_end: [integer,integer]? }

---@class obsidian.PickerSelectOpts
---
---@field prompt string|?
---@field kind string|?
---@field allow_multiple boolean|?
---@field no_default_mappings boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?
---@field format_item (fun(value: any): string)|?
---@field preview_item (fun(value: any): obsidian.ui_select_preview_spec)?
---@field query string|?
---
---@class obsidian.PickerEntryUserData
---@field attachment boolean|?
---@field missing boolean|?
---@field references obsidian.NoteCreationReference[]|?
---@field target string|?
---
---@class obsidian.PickerPickOpts: obsidian.PickerSelectOpts
---
---@field prompt_title string|?
---@field callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?

------------------------------------------------------------------
--- Concrete methods with a default implementation subclasses. ---
------------------------------------------------------------------

--- Backwards-compatible shim for the old picker API.
---
---@param values string[]|obsidian.PickerEntry[] Items to pick from.
---@param opts obsidian.PickerPickOpts|? Options.
local pick = function(values, opts)
  opts = opts or {}

  local select_opts = vim.tbl_extend("force", {}, opts, {
    prompt = opts.prompt or opts.prompt_title,
    callback = nil,
    prompt_title = nil,
  })

  return M.select(values, select_opts, function(choices)
    if not choices or #choices == 0 then
      return
    end

    if opts.callback then
      choices = vim.tbl_map(function(choice)
        if type(choice) == "string" then
          return { value = choice, user_data = choice, text = choice }
        else
          return choice
        end
      end, choices)
      opts.callback(unpack(choices))
    else
      picker_util.open_notes(choices)
    end
  end)
end

M.pick = pick

--- Find files using the shared filesystem iterator and present them with the active picker.
---
---@param opts obsidian.PickerFindOpts?
local find_files = function(opts)
  opts = opts or {}

  -- search.find_async() resolves its root before enumerating files. Use the
  -- same canonical root here so aliases such as macOS's /var -> /private/var
  -- and Windows short paths remain relative to the picker directory.
  local dir = Path.new(opts.dir or api.resolve_workspace_dir()):resolve { strict = true }
  local paths = {}
  search.find_async(dir, nil, {
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
    include_non_markdown = opts.include_non_markdown,
  }, function(path)
    paths[#paths + 1] = path
  end, function(code)
    if code ~= 0 then
      log.err("Failed to enumerate files in '%s'", dir)
      return
    end

    M.select(paths, {
      prompt = opts.prompt_title,
      allow_multiple = true,
      query = opts.query,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      format_item = function(path)
        return icons.get_path_icon(path) .. " " .. tostring(Path.new(path):relative_to(dir))
      end,
      preview_item = util.preview_path,
    }, function(items)
      local callback = opts.callback or picker_util.open_notes
      callback(items)
    end)
  end)
end

M.find_files = find_files

--- Find notes by filename.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(paths: string[])|?, no_default_mappings: boolean|?, dir: obsidian.Path|?, show_existing_only: boolean|?, show_attachments: boolean|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected note paths.
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
    dir = opts.dir or api.resolve_workspace_dir(),
    callback = opts.callback,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
    use_cache = true,
    show_existing_only = opts.show_existing_only,
    show_attachments = opts.show_attachments,
  }
end

--- Grep search in notes.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(entries: obsidian.PickerEntry[])|?, no_default_mappings: boolean|?, dir: obsidian.Path|? }|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `query`: Initial query to grep for.
---  `callback`: Callback to run with the selected entries.
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
    dir = opts.dir or api.resolve_workspace_dir(),
    query = opts.query,
    callback = opts.callback,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
  }
end

--- Removed picker API. Use `picker.select` directly.
M.pick_note = function()
  error "picker.pick_note has been removed; use picker.select instead"
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

  local note_mappings = Obsidian.opts.picker.note_mappings or {}
  if key_is_set(note_mappings.new) then
    mappings[note_mappings.new] = {
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

  local note_mappings = Obsidian.opts.picker.note_mappings or {}
  if key_is_set(note_mappings.insert_link) then
    mappings[note_mappings.insert_link] = {
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

  local tag_mappings = Obsidian.opts.picker.tag_mappings or {}
  if key_is_set(tag_mappings.tag_note) then
    mappings[tag_mappings.tag_note] = {
      desc = "tag note",
      callback = Mappings.tag_note,
      fallback_to_query = true,
      keep_open = true,
      allow_multiple = true,
    }
  end

  if key_is_set(tag_mappings.insert_tag) then
    mappings[tag_mappings.insert_tag] = {
      desc = "insert tag",
      callback = Mappings.insert_tag,
      fallback_to_query = true,
    }
  end

  return mappings
end

local function patch(modname)
  local picker = require(modname)
  local picker_find_files = picker.find_files or find_files
  M.find_files = function(opts)
    opts = opts or {}
    if require("obsidian.cache").find_files(opts) then
      return
    end
    picker_find_files(opts)
  end

  for name, f in pairs(picker) do
    if name ~= "pick" and name ~= "find_files" then
      M[name] = f
    end
  end
end

---@param picker_name obsidian.config.Picker|?
---@return string
local function picker_module(picker_name)
  if picker_name == string.lower(PickerName.telescope) then
    return "obsidian.picker.telescope"
  elseif picker_name == string.lower(PickerName.mini) then
    return "obsidian.picker.mini"
  elseif picker_name == string.lower(PickerName.fzf_lua) then
    return "obsidian.picker.fzf"
    -- or statement added for backwards compatibility
  elseif picker_name == string.lower(PickerName.snacks) or picker_name == "snacks.pick" then
    return "obsidian.picker.snacks"
  else
    return "obsidian.picker.default"
  end
end

local function resolve_picker()
  if state.picker_resolved then
    return
  end

  local picker_name = state.picker_name
  if picker_name then
    if not picker_available(picker_name) then
      log.warn_once('Configured picker "%s" is not available; falling back to native picker', picker_name)
      patch "obsidian.picker.default"
      state.picker_resolved = true
      return
    end
  else
    for _, name in ipairs { PickerName.telescope, PickerName.fzf_lua, PickerName.mini, PickerName.snacks } do
      if picker_available(name) then
        picker_name = string.lower(name)
        break
      end
    end
  end

  patch(picker_module(picker_name))
  state.picker_resolved = true
end

---@param method string
---@return function
local function lazy_picker_method(method)
  local lazy_method
  lazy_method = function(...)
    resolve_picker()
    local resolved_method = M[method]
    if resolved_method == lazy_method then
      error(string.format("picker method '%s' is not implemented", method))
    end
    return resolved_method(...)
  end
  return lazy_method
end

--- Get the default Picker.
---
---@param picker_name obsidian.config.Picker|false|?
M.get = function(picker_name)
  state.picker_resolved = false
  state.picker_name = nil
  M.pick = pick

  if picker_name == false then
    patch "obsidian.picker.default"
    state.picker_resolved = true
    return M
  end

  if picker_name then
    state.picker_name = string.lower(picker_name)
  end

  M.find_files = find_files
  M.grep = lazy_picker_method "grep"
  M.select = lazy_picker_method "select"

  return M
end

return M
