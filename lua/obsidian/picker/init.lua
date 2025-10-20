local abc = require "obsidian.abc"
local log = require "obsidian.log"
local api = require "obsidian.api"
local util = require "obsidian.util"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local search = require "obsidian.search"

---@class obsidian.Picker : obsidian.ABC
---
---@field calling_bufnr integer
local Picker = abc.new_class()

Picker.new = function()
  local self = Picker.init()
  self.calling_bufnr = vim.api.nvim_get_current_buf()
  return self
end

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

--- Find files in a directory.
---
---@param opts obsidian.PickerFindOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `dir`: Directory to search in.
---  `callback`: Callback to run with the selected entry.
---  `no_default_mappings`: Don't apply picker's default mappings.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
Picker.find_files = function(self, opts)
  opts = opts or {}

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title .. ": ") -- TODO:
  end

  if not query then
    return
  end

  local paths = {}

  search.find_async(
    opts.dir,
    query,
    {},
    function(path)
      paths[#paths + 1] = path
    end,
    vim.schedule_wrap(function()
      if vim.tbl_isempty(paths) then
        return log.info "Failed to Switch" -- TODO:
      elseif #paths == 1 then
        return api.open_buffer(paths[1])
      elseif #paths > 1 then
        ---@type vim.quickfix.entry
        local items = {}
        for _, path in ipairs(paths) do
          items[#items + 1] = {
            filename = path,
            lnum = 1,
            col = 0,
            text = self:_make_display {
              filename = path,
            },
          }
        end
        if opts.select then
          vim.ui.select(items, {
            format_item = function(item)
              return item.text
            end,
          }, function(item, idx)
            if opts.callback then
              opts.callback(item.filename)
            end
          end)
        else
          vim.fn.setqflist(items)
          vim.cmd "copen"
        end
      end
    end)
  )
end

---@class obsidian.PickerGrepOpts
---
---@field prompt_title string|?
---@field dir string|obsidian.Path|?
---@field query string|?
---@field callback fun(entry: obsidian.PickerEntry)|?
---@field no_default_mappings boolean|?
---@field query_mappings obsidian.PickerMappingTable
---@field selection_mappings obsidian.PickerMappingTable

--- Grep for a string.
---
---@param opts obsidian.PickerGrepOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `dir`: Directory to search in.
---  `query`: Initial query to grep for.
---  `callback`: Callback to run with the selected path.
---  `no_default_mappings`: Don't apply picker's default mappings.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
Picker.grep = function(_, opts)
  opts = opts or {}

  ---@param match MatchData
  ---@return vim.quickfix.entry
  local function match_data_to_qfitem(match)
    local filename = match.path.text
    return {
      filename = filename,
      lnum = match.line_number,
      col = match.submatches[1].start + 1,
      text = match.lines.text,
    }
  end

  local query
  if opts.query and vim.trim(opts.query) ~= "" then
    query = opts.query
  else
    query = api.input(opts.prompt_title .. ": ") -- TODO:
  end

  if not query then
    return
  end

  local items = {}

  search.search_async(
    opts.dir,
    query,
    {},
    function(match)
      items[#items + 1] = match_data_to_qfitem(match)
    end,
    vim.schedule_wrap(function(code)
      assert(code == 0, "failed to run ripgrep")

      if vim.tbl_isempty(items) then
        return log.info "Failed to Grep"
      elseif #items == 1 then
        local item = items[1]
        return api.open_buffer(item.filename, {
          line = item.lnum,
          col = item.col,
        })
      else
        vim.fn.setqflist(items)
        vim.cmd "copen"
      end
    end)
  )
end

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

--- Pick from a list of items.
---
---@param values string[]|obsidian.PickerEntry[] Items to pick from.
---@param opts obsidian.PickerPickOpts|? Options.
---
--- Options:
---  `prompt_title`: Title for the prompt window.
---  `callback`: Callback to run with the selected item(s).
---  `allow_multiple`: Allow multiple selections to pass to the callback.
---  `query_mappings`: Mappings that run with the query prompt.
---  `selection_mappings`: Mappings that run with the current selection.
---
Picker.pick = function(self, values, opts)
  opts = opts or {}
  vim.ui.select(values, {
    prompt = opts.prompt_title,
    format_item = opts.format_item or function(value)
      return self:_make_display(value)
    end,
  }, function(item)
    if opts.callback then
      opts.callback(item)
    end
  end)
end

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
Picker.find_notes = function(self, opts)
  self.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = self:_note_query_mappings()
    selection_mappings = self:_note_selection_mappings()
  end

  return self:find_files {
    select = opts.select, -- TODO:
    query = opts.query,
    prompt_title = opts.prompt_title or "Notes",
    dir = Obsidian.dir,
    callback = opts.callback or api.open_buffer,
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
Picker.grep_notes = function(self, opts)
  self.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = self:_note_query_mappings()
    selection_mappings = self:_note_selection_mappings()
  end

  self:grep {
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
Picker.pick_note = function(self, notes, opts)
  self.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  local query_mappings
  local selection_mappings
  if not opts.no_default_mappings then
    query_mappings = self:_note_query_mappings()
    selection_mappings = self:_note_selection_mappings()
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

  self:pick(entries, {
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
Picker._note_query_mappings = function()
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if Obsidian.opts.picker.note_mappings and key_is_set(Obsidian.opts.picker.note_mappings.new) then
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
Picker._note_selection_mappings = function()
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if Obsidian.opts.picker.note_mappings and key_is_set(Obsidian.opts.picker.note_mappings.insert_link) then
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
Picker._tag_selection_mappings = function(self)
  ---@type obsidian.PickerMappingTable
  local mappings = {}

  if Obsidian.opts.picker.tag_mappings then
    if key_is_set(Obsidian.opts.picker.tag_mappings.tag_note) then
      mappings[Obsidian.opts.picker.tag_mappings.tag_note] = {
        desc = "tag note",
        callback = function(...)
          local tags = vim.tbl_map(function(value)
            return value.value
          end, { ... })

          local note = api.current_note(self.calling_bufnr)
          if not note then
            log.warn("'%s' is not a note in your workspace", vim.api.nvim_buf_get_name(self.calling_bufnr))
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
            if note:update_frontmatter(self.calling_bufnr) then
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
  end

  return mappings
end

---@param opts { prompt_title: string, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|? }|?
---@return string
Picker._build_prompt = function(_, opts)
  opts = opts or {}

  ---@type string
  local prompt = opts.prompt_title or "Find"
  if string.len(prompt) > 50 then
    prompt = string.sub(prompt, 1, 50) .. "…"
  end

  prompt = prompt .. " | <CR> confirm"

  if opts.query_mappings then
    local keys = vim.tbl_keys(opts.query_mappings)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local mapping = opts.query_mappings[key]
      prompt = prompt .. " | " .. key .. " " .. mapping.desc
    end
  end

  if opts.selection_mappings then
    local keys = vim.tbl_keys(opts.selection_mappings)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local mapping = opts.selection_mappings[key]
      prompt = prompt .. " | " .. key .. " " .. mapping.desc
    end
  end

  return prompt
end

---@param entry obsidian.PickerEntry
---
---@return string, { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
Picker._make_display = function(_, entry)
  local buf = {}
  ---@type { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
  local highlights = {}

  local icon, icon_hl

  if entry.icon then
    icon = entry.icon
    icon_hl = entry.icon_hl
  else
    icon, icon_hl = api.get_icon(entry.filename)
  end

  if icon then
    buf[#buf + 1] = icon
    buf[#buf + 1] = " "
    if icon_hl then
      highlights[#highlights + 1] = { { 0, util.strdisplaywidth(icon) }, icon_hl }
    end
  end

  if entry.filename then
    buf[#buf + 1] = Path.new(entry.filename):vault_relative_path()

    if entry.lnum ~= nil then
      buf[#buf + 1] = ":"
      buf[#buf + 1] = entry.lnum

      if entry.col ~= nil then
        buf[#buf + 1] = ":"
        buf[#buf + 1] = entry.col
      end
    end
  end

  if entry.display then
    buf[#buf + 1] = " "
    buf[#buf + 1] = entry.display
  elseif entry.value then
    buf[#buf + 1] = " "
    buf[#buf + 1] = tostring(entry.value)
  end

  return table.concat(buf, ""), highlights
end

local PickerName = require("obsidian.config").Picker

--- Get the default Picker.
---
---@param picker_name obsidian.config.Picker|?
---
---@return obsidian.Picker|?
Picker.get = function(picker_name)
  picker_name = picker_name and picker_name or Obsidian.opts.picker.name
  if picker_name then
    picker_name = string.lower(picker_name)
  elseif picker_name == false then
    return Picker.new()
  else
    for _, name in ipairs { PickerName.telescope, PickerName.fzf_lua, PickerName.mini, PickerName.snacks } do
      local ok, res = pcall(Picker.get, name)
      if ok then
        return res
      end
    end
    return Picker.new()
  end

  if picker_name == string.lower(PickerName.telescope) then
    return require("obsidian.picker._telescope").new()
  elseif picker_name == string.lower(PickerName.mini) then
    return require("obsidian.picker._mini").new()
  elseif picker_name == string.lower(PickerName.fzf_lua) then
    return require("obsidian.picker._fzf").new()
  elseif picker_name == string.lower(PickerName.snacks) then
    return require("obsidian.picker._snacks").new()
  elseif picker_name then
    error("not implemented for " .. picker_name)
  end
end

return Picker
