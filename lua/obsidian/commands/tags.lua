local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@class obsidian.commands.tags.Query
---@field tags string[]
---@field and_mode boolean
---@field inline_only boolean

---@param tag string
---@return string
local function normalize(tag)
  tag = vim.trim(tag):lower():gsub("%s+", "")
  while vim.startswith(tag, "+") or vim.startswith(tag, "#") do
    tag = tag:sub(2)
  end
  return tag
end

---@param tag string
---@return boolean and_mode
---@return boolean inline_only
local function parse_modifiers(tag)
  local and_mode = false
  local inline_only = false
  tag = vim.trim(tag)

  while vim.startswith(tag, "+") or vim.startswith(tag, "#") do
    if vim.startswith(tag, "+") then
      and_mode = true
    elseif vim.startswith(tag, "#") then
      inline_only = true
    end
    tag = tag:sub(2)
  end

  return and_mode, inline_only
end

---@param args string[]
---@return obsidian.commands.tags.Query
local function parse_args(args)
  local query = {
    tags = {},
    and_mode = false,
    inline_only = false,
  }
  local seen = {}

  for _, arg in ipairs(args or {}) do
    if type(arg) == "string" and vim.trim(arg) ~= "" then
      local and_mode, inline_only = parse_modifiers(arg)
      query.and_mode = query.and_mode or and_mode
      query.inline_only = query.inline_only or inline_only

      local tag = normalize(arg)
      if tag ~= "" and not seen[tag] then
        seen[tag] = true
        query.tags[#query.tags + 1] = tag
      end
    end
  end

  return query
end

---@param query_tag string
---@param tag string
---@return boolean
local function tag_matches(query_tag, tag)
  tag = normalize(tag)
  return tag == query_tag or vim.startswith(tag, query_tag .. "/")
end

---@param tag_locations obsidian.TagLocation[]
---@return string[]
local function list_tags(tag_locations)
  local tags = {}
  for _, tag_loc in ipairs(tag_locations) do
    local tag = normalize(tag_loc.tag)
    if tag ~= "" then
      tags[tag] = true
    end
  end

  local unique = vim.tbl_keys(tags)
  table.sort(unique)
  return unique
end

---@param loc obsidian.TagLocation
---@param query obsidian.commands.tags.Query
---@return boolean
local function loc_matches_source(loc, query)
  return not query.inline_only or loc.inline == true
end

---@class obsidian.commands.tags.NoteMatch
---@field note obsidian.Note
---@field path string|obsidian.Path
---@field tags table<string, boolean>
---@field locs obsidian.TagLocation[]

---@param tag_locations obsidian.TagLocation[]
---@param query obsidian.commands.tags.Query
---@return table<string, obsidian.commands.tags.NoteMatch>, string[]
local function collect_note_matches(tag_locations, query)
  local notes = {}
  local note_order = {}

  for _, loc in ipairs(tag_locations) do
    if loc_matches_source(loc, query) then
      local matched = false
      local key = tostring(loc.path)

      for _, query_tag in ipairs(query.tags) do
        if tag_matches(query_tag, loc.tag) then
          if notes[key] == nil then
            notes[key] = {
              note = loc.note,
              path = loc.path,
              tags = {},
              locs = {},
            }
            note_order[#note_order + 1] = key
          end

          notes[key].tags[query_tag] = true
          matched = true
        end
      end

      if matched then
        notes[key].locs[#notes[key].locs + 1] = loc
      end
    end
  end

  return notes, note_order
end

---@param note_match obsidian.commands.tags.NoteMatch
---@param query obsidian.commands.tags.Query
---@return boolean
local function note_matches_query(note_match, query)
  if query.and_mode then
    for _, query_tag in ipairs(query.tags) do
      if not note_match.tags[query_tag] then
        return false
      end
    end
    return true
  end

  return not vim.tbl_isempty(note_match.tags)
end

---@param loc obsidian.TagLocation
---@return obsidian.PickerEntry
local function tag_location_to_entry(loc)
  local display = string.format("%s [%s] %s", loc.note:display_name(), loc.line, loc.text)
  return {
    value = { path = loc.path, line = loc.line, col = loc.tag_start },
    display = display,
    ordinal = display,
    filename = tostring(loc.path),
    lnum = loc.line,
    col = loc.tag_start,
  }
end

---@param note_match obsidian.commands.tags.NoteMatch
---@param query obsidian.commands.tags.Query
---@return obsidian.PickerEntry
local function note_match_to_entry(note_match, query)
  local matched_tags = {}
  for _, query_tag in ipairs(query.tags) do
    if note_match.tags[query_tag] then
      matched_tags[#matched_tags + 1] = query_tag
    end
  end

  local mode = query.and_mode and "AND" or "OR"
  local display = string.format("%s [%s: %s]", note_match.note:display_name(), mode, table.concat(matched_tags, ", "))
  return {
    value = { path = note_match.path },
    display = display,
    ordinal = display,
    filename = tostring(note_match.path),
  }
end

---@param query obsidian.commands.tags.Query
---@return string
local function prompt_title(query)
  local mode = query.and_mode and "AND" or "OR"
  if query.inline_only then
    mode = mode .. " inline"
  end
  return string.format("%s: #%s", mode, table.concat(query.tags, ", #"))
end

---@param query obsidian.commands.tags.Query
---@return boolean
local function should_show_locations(query)
  return query.inline_only or #query.tags == 1
end

---@param tag_locations obsidian.TagLocation[]
---@param args string[]
local function open_picker(tag_locations, args)
  local query = parse_args(args)
  if vim.tbl_isempty(query.tags) then
    log.warn "No tag provided"
    return
  end

  local notes, note_order = collect_note_matches(tag_locations, query)

  ---@type obsidian.PickerEntry[]
  local entries = {}
  for _, key in ipairs(note_order) do
    local note_match = notes[key]
    if note_matches_query(note_match, query) then
      if should_show_locations(query) then
        for _, loc in ipairs(note_match.locs) do
          entries[#entries + 1] = tag_location_to_entry(loc)
        end
      else
        entries[#entries + 1] = note_match_to_entry(note_match, query)
      end
    end
  end

  if vim.tbl_isempty(entries) then
    if #query.tags == 1 then
      log.warn "Tag not found"
    else
      log.warn "Tags not found"
    end
    return
  end

  vim.schedule(function()
    Obsidian.picker.pick(entries, {
      prompt_title = prompt_title(query),
    })
  end)
end

---@param tag_locations obsidian.TagLocation[]
local function open_tag_list_picker(tag_locations)
  local tags = list_tags(tag_locations)
  if vim.tbl_isempty(tags) then
    log.warn "Tags not found"
    return
  end

  vim.schedule(function()
    Obsidian.picker.pick(tags, {
      callback = function(...)
        local selected_tags = vim.tbl_map(function(value)
          return value.user_data
        end, { ... })
        open_picker(tag_locations, selected_tags)
      end,
      selection_mappings = Obsidian.picker._tag_selection_mappings(),
      allow_multiple = true,
    })
  end)
end

---@param data obsidian.CommandArgs
return function(data)
  local args = data.fargs or {}
  local dir = api.resolve_workspace_dir()

  if vim.tbl_isempty(args) then
    local tag = api.cursor_tag()
    if tag then
      args = { tag }
    end
  end

  if vim.tbl_isempty(args) then
    search.find_tags_async("", open_tag_list_picker, { dir = dir })
    return
  end

  local query = parse_args(args)
  if vim.tbl_isempty(query.tags) then
    log.warn "No tag provided"
    return
  end

  search.find_tags_async(query.tags, function(tag_locations)
    open_picker(tag_locations, args)
  end, { dir = dir })
end
