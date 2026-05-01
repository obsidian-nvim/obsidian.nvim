local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@class obsidian.commands.tags.QueryTerm
---@field tag string
---@field negated boolean

---@class obsidian.commands.tags.QueryClause
---@field terms obsidian.commands.tags.QueryTerm[]

---@class obsidian.commands.tags.Query
---@field clauses obsidian.commands.tags.QueryClause[]
---@field positive_tags string[]
---@field raw string

---@class obsidian.commands.tags.NoteMatch
---@field note obsidian.Note
---@field path string|obsidian.Path
---@field tags string[]
---@field locs obsidian.TagLocation[]

---@param tag string
---@return string
local function normalize_tag(tag)
  tag = vim.trim(tag):lower()
  while vim.startswith(tag, "#") do
    tag = tag:sub(2)
  end
  return tag
end

---@param query_tag string
---@param tag string
---@return boolean
local function tag_matches(query_tag, tag)
  tag = normalize_tag(tag)
  return tag == query_tag or vim.startswith(tag, query_tag .. "/")
end

---@param token string
---@return obsidian.commands.tags.QueryTerm|nil, string|nil
local function parse_term(token)
  token = vim.trim(token)
  if token == "" then
    return nil, nil
  end

  local negated = false
  if vim.startswith(token, "-") then
    negated = true
    token = token:sub(2)
  end

  if vim.startswith(token:lower(), "tag:") then
    token = token:sub(5)
  elseif token:find(":", 1, true) then
    return nil, "Unsupported search term '" .. token .. "'"
  end

  local tag = normalize_tag(token)
  if tag == "" then
    return nil, nil
  end

  return {
    tag = tag,
    negated = negated,
  }, nil
end

---@param args string[]
---@return obsidian.commands.tags.Query|nil, string|nil
local function parse_query(args)
  ---@type obsidian.commands.tags.Query
  local query = {
    clauses = {},
    positive_tags = {},
    raw = "",
  }

  local current_clause = { terms = {} }
  local positive_seen = {}

  for _, token in ipairs(args or {}) do
    token = vim.trim(token)
    if token ~= "" then
      if token:upper() == "OR" then
        if not vim.tbl_isempty(current_clause.terms) then
          query.clauses[#query.clauses + 1] = current_clause
          current_clause = { terms = {} }
        end
      else
        local term, err = parse_term(token)
        if err ~= nil then
          return nil, err
        elseif term ~= nil then
          current_clause.terms[#current_clause.terms + 1] = term
          if not term.negated and not positive_seen[term.tag] then
            positive_seen[term.tag] = true
            query.positive_tags[#query.positive_tags + 1] = term.tag
          end
        end
      end
    end
  end

  if not vim.tbl_isempty(current_clause.terms) then
    query.clauses[#query.clauses + 1] = current_clause
  end

  if vim.tbl_isempty(query.clauses) then
    return nil, "No tag provided"
  elseif vim.tbl_isempty(query.positive_tags) then
    return nil, "At least one positive tag term is required"
  end

  local parts = {}
  for idx, clause in ipairs(query.clauses) do
    if idx > 1 then
      parts[#parts + 1] = "OR"
    end
    for _, term in ipairs(clause.terms) do
      parts[#parts + 1] = (term.negated and "-" or "") .. "tag:#" .. term.tag
    end
  end
  query.raw = table.concat(parts, " ")

  return query, nil
end

---@param tag_locations obsidian.TagLocation[]
---@return string[]
local function list_tags(tag_locations)
  local tags = {}
  for _, tag_loc in ipairs(tag_locations) do
    local tag = normalize_tag(tag_loc.tag)
    if tag ~= "" then
      tags[tag] = true
    end
  end

  local unique = vim.tbl_keys(tags)
  table.sort(unique)
  return unique
end

---@param tag_locations obsidian.TagLocation[]
---@return table<string, obsidian.commands.tags.NoteMatch>, string[]
local function collect_note_matches(tag_locations)
  local notes = {}
  local note_order = {}

  for _, loc in ipairs(tag_locations) do
    local key = tostring(loc.path)
    if notes[key] == nil then
      notes[key] = {
        note = loc.note,
        path = loc.path,
        tags = {},
        locs = {},
      }
      note_order[#note_order + 1] = key
    end

    local note_match = notes[key]
    note_match.tags[#note_match.tags + 1] = normalize_tag(loc.tag)
    note_match.locs[#note_match.locs + 1] = loc
  end

  return notes, note_order
end

---@param note_match obsidian.commands.tags.NoteMatch
---@param query_tag string
---@return boolean
local function note_has_tag(note_match, query_tag)
  for _, tag in ipairs(note_match.tags) do
    if tag_matches(query_tag, tag) then
      return true
    end
  end

  return false
end

---@param note_match obsidian.commands.tags.NoteMatch
---@param query obsidian.commands.tags.Query
---@return table<string, boolean>|nil
local function matched_positive_tags(note_match, query)
  local matched = {}
  local matched_any = false

  for _, clause in ipairs(query.clauses) do
    local clause_matches = true
    local clause_positive = {}

    for _, term in ipairs(clause.terms) do
      local has_tag = note_has_tag(note_match, term.tag)
      if term.negated then
        if has_tag then
          clause_matches = false
          break
        end
      else
        if not has_tag then
          clause_matches = false
          break
        end
        clause_positive[term.tag] = true
      end
    end

    if clause_matches then
      matched_any = true
      for tag, value in pairs(clause_positive) do
        matched[tag] = value
      end
    end
  end

  if matched_any then
    return matched
  else
    return nil
  end
end

---@param loc obsidian.TagLocation
---@param positive_tags table<string, boolean>
---@return boolean
local function location_matches(loc, positive_tags)
  for query_tag, _ in pairs(positive_tags) do
    if tag_matches(query_tag, loc.tag) then
      return true
    end
  end

  return false
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

---@param tag_locations obsidian.TagLocation[]
---@param query obsidian.commands.tags.Query
local function open_query_results(tag_locations, query)
  local notes, note_order = collect_note_matches(tag_locations)

  ---@type obsidian.PickerEntry[]
  local entries = {}
  local seen = {}

  for _, key in ipairs(note_order) do
    local note_match = notes[key]
    local positive_tags = matched_positive_tags(note_match, query)
    if positive_tags ~= nil then
      for _, loc in ipairs(note_match.locs) do
        if location_matches(loc, positive_tags) then
          local loc_key = table.concat({
            tostring(loc.path),
            tostring(loc.line),
            tostring(loc.tag_start),
            tostring(loc.tag_end),
            normalize_tag(loc.tag),
          }, ":")
          if not seen[loc_key] then
            seen[loc_key] = true
            entries[#entries + 1] = tag_location_to_entry(loc)
          end
        end
      end
    end
  end

  if vim.tbl_isempty(entries) then
    log.warn "Tags not found"
    return
  end

  vim.schedule(function()
    Obsidian.picker.pick(entries, {
      prompt_title = "Tags: " .. query.raw,
    })
  end)
end

---@param tags string[]
---@return string[]
local function tags_to_query_args(tags)
  local args = {}
  for _, tag in ipairs(tags) do
    local normalized = normalize_tag(tag)
    if normalized ~= "" then
      args[#args + 1] = "tag:#" .. normalized
    end
  end
  return args
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
        local query, err = parse_query(tags_to_query_args(selected_tags))
        if err ~= nil then
          log.warn(err)
          return
        end
        open_query_results(tag_locations, query)
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
      args = { "tag:" .. tag }
    end
  end

  if vim.tbl_isempty(args) then
    search.find_tags_async("", open_tag_list_picker, { dir = dir })
    return
  end

  local query, err = parse_query(args)
  if err ~= nil then
    log.warn(err)
    return
  end

  search.find_tags_async("", function(tag_locations)
    open_query_results(tag_locations, query)
  end, { dir = dir })
end
