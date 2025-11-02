local log = require "obsidian.log"
local api = require "obsidian.api"
local Note = require "obsidian.note"
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
---@field callback fun(...)
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

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(entry: obsidian.PickerEntry)|?
---@field no_default_mappings boolean|?
---@field query_mappings obsidian.PickerMappingTable
---@field selection_mappings obsidian.PickerMappingTable

---@class obsidian.PickerEntry
---
---@field value any
---@field ordinal string|?
---@field display string|?
---@field filename string|?
---@field valid boolean|?
---@field lnum integer|?
---@field col integer|?
---@field icon string|?
---@field icon_hl string|?

---@class obsidian.PickerPickOpts
---
---@field prompt_title string|?
---@field callback fun(value: obsidian.PickerEntry, ...: obsidian.PickerEntry)|?
---@field allow_multiple boolean|?
---@field query_mappings obsidian.PickerMappingTable|?
---@field selection_mappings obsidian.PickerMappingTable|?
---@field format_item (fun(value: obsidian.PickerEntry): string)|?

------------------------------------------------------------------
--- Concrete methods with a default implementation subclasses. ---
------------------------------------------------------------------

--- Find notes by filename.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(path: string)|?, no_default_mappings: boolean|? }|? Options.
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

  return M.find_files {
    query = opts.query,
    prompt_title = opts.prompt_title or "Notes",
    dir = Obsidian.dir,
    callback = opts.callback, -- TODO: breaks picker plugin integration?
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
  }
end

--- Grep search in notes.
---
---@param opts { prompt_title: string|?, query: string|?, callback: fun(entry: obsidian.PickerEntry)|?, no_default_mappings: boolean|? }|? Options.
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
    dir = Obsidian.dir,
    query = opts.query,
    callback = opts.callback or function(v)
      return api.open_buffer(v.filename, { line = v.lnum, col = v.col })
    end,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
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
---  `no_default_mappings`: Don't apply picker's default mappings.
M.pick_note = function(notes, opts)
  state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = M._note_query_mappings()
    selection_mappings = M._note_selection_mappings()
  end

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
      opts.callback(v.value)
    end,
    allow_multiple = opts.allow_multiple,
    no_default_mappings = opts.no_default_mappings,
    query_mappings = query_mappings,
    selection_mappings = selection_mappings,
  })
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
      callback = function(query)
        ---@diagnostic disable-next-line: missing-fields
        require "obsidian.commands.new" { args = query }
      end,
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
      callback = function(note_or_path)
        ---@type obsidian.Note
        local note
        if Note.is_note_obj(note_or_path) then
          note = note_or_path
        else
          note = Note.from_file(note_or_path)
        end
        local link = note:format_link()
        vim.api.nvim_put({ link }, "", false, true)
        require("obsidian.ui").update(0)
      end,
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
      callback = function(...)
        local tags = vim.tbl_map(function(value)
          return value.value
        end, { ... })

        local note = api.current_note(state.calling_bufnr)
        if not note then
          log.warn("'%s' is not a note in your workspace", vim.api.nvim_buf_get_name(M.state.calling_bufnr))
          return
        end

        -- Add the tag and save the new frontmatter to the buffer.
        local tags_added = {}
        local tags_not_added = {}
        for _, tag in ipairs(tags) do
          if note:add_tag(tag) then
            table.insert(tags_added, tag)
          else
            table.insert(tags_not_added, tag)
          end
        end

        if #tags_added > 0 then
          if note:update_frontmatter(M.state.calling_bufnr) then
            log.info("Added tags %s to frontmatter", tags_added)
          else
            log.warn "Frontmatter unchanged"
          end
        end

        if #tags_not_added > 0 then
          log.warn("Note already has tags %s", tags_not_added)
        end
      end,
      fallback_to_query = true,
      keep_open = true,
      allow_multiple = true,
    }
  end

  if key_is_set(Obsidian.opts.picker.tag_mappings.insert_tag) then
    mappings[Obsidian.opts.picker.tag_mappings.insert_tag] = {
      desc = "insert tag",
      callback = function(item)
        local tag = item.value
        vim.api.nvim_put({ "#" .. tag }, "", false, true)
      end,
      fallback_to_query = true,
    }
  end

  return mappings
end

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
