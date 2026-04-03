local M = {}

local Note = require "obsidian.note"
local Path = require "obsidian.path"
local api = require "obsidian.api"
local search = require "obsidian.search"
local util = require "obsidian.util"

local lookup_cache = {
  vault = nil,
  reference_lookup = nil,
  absolute_lookup = nil,
}

---@class obsidian.analysis.DeadLinkEntry
---@field path obsidian.Path
---@field filename string
---@field line integer
---@field start integer
---@field end_col integer
---@field link string
---@field location string
---@field text string

---@param location string
---@return string[]
local function path_location_candidates(location)
  local candidates = {
    location,
    location:gsub("^%./", ""),
    location:gsub("^/", ""),
    vim.uri_decode(location),
  }

  local dedup = {}
  local out = {}
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and not dedup[candidate] then
      dedup[candidate] = true
      out[#out + 1] = candidate
    end
  end
  return out
end

---@param notes obsidian.Note[]
---@return table<string, string>
---@return table<string, string>
local function build_note_lookups(notes)
  local reference_lookup = {}
  local absolute_lookup = {}

  for _, note in ipairs(notes) do
    local abs = tostring(note.path:resolve())
    local abs_key = abs:lower()
    absolute_lookup[abs_key] = abs
    reference_lookup[abs_key] = abs

    for _, ref in ipairs(note:get_reference_paths { urlencode = true }) do
      local key = ref:lower()
      if not reference_lookup[key] then
        reference_lookup[key] = abs
      end
    end

    for _, alias in ipairs(note.aliases) do
      local key = alias:lower()
      if not reference_lookup[key] then
        reference_lookup[key] = abs
      end
    end
  end

  return reference_lookup, absolute_lookup
end

---@return obsidian.Note[]
local function collect_workspace_notes()
  ---@type obsidian.Note[]
  local notes = {}
  for path in api.dir(Obsidian.dir) do
    local ok, note = pcall(Note.from_file, path)
    if ok and note then
      notes[#notes + 1] = note
    end
  end
  return notes
end

---@param source_path obsidian.Path
---@param location string
---@param reference_lookup table<string, string>
---@param absolute_lookup table<string, string>
---@return string|nil
local function resolve_target_path(source_path, location, reference_lookup, absolute_lookup)
  for _, candidate in ipairs(path_location_candidates(location)) do
    local reference_hit = reference_lookup[candidate:lower()]
    if reference_hit then
      return reference_hit
    end

    local parent = source_path:parent()
    if parent ~= nil then
      local resolved = tostring((parent / candidate):resolve())
      local absolute_hit = absolute_lookup[resolved:lower()]
      if absolute_hit then
        return absolute_hit
      end
    end
  end

  return nil
end

---@param source_path obsidian.Path
---@param text string
---@param reference_lookup table<string, string>
---@param absolute_lookup table<string, string>
---@return obsidian.analysis.DeadLinkEntry[]
local function collect_dead_links_from_text(source_path, text, reference_lookup, absolute_lookup)
  ---@type obsidian.analysis.DeadLinkEntry[]
  local entries = {}
  local lines = vim.split(text, "\n")
  local seen = {}

  for line_idx, line in ipairs(lines) do
    for _, ref_match in ipairs(search.find_refs(line, { exclude = { "BlockID", "Tag" } })) do
      local m_start, m_end, ref_type = unpack(ref_match)
      local link = line:sub(m_start, m_end)
      local location, _, link_type = util.parse_link(link, { strip = true, link_type = ref_type })

      if location and location ~= "" and link_type ~= "HeaderLink" and link_type ~= "BlockLink" then
        local is_uri = util.is_uri(location)
        if not is_uri and not api.is_attachment_path(location) then
          local target = resolve_target_path(source_path, location, reference_lookup, absolute_lookup)
          if target == nil then
            local key = table.concat({ tostring(line_idx), tostring(m_start), tostring(m_end), location }, ":")
            if not seen[key] then
              seen[key] = true
              entries[#entries + 1] = {
                path = source_path,
                filename = tostring(source_path),
                line = line_idx,
                start = m_start - 1,
                end_col = m_end,
                link = link,
                location = location,
                text = line,
              }
            end
          end
        end
      end
    end
  end

  return entries
end

---@param source_path obsidian.Path
---@return string
local function read_source_text(source_path)
  local filename = tostring(source_path)
  local bufnr = vim.fn.bufnr(filename, false)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end

  local ok, lines = pcall(vim.fn.readfile, filename)
  if ok and lines then
    return table.concat(lines, "\n")
  end

  return ""
end

---@return table<string, string>
---@return table<string, string>
local function get_note_lookups()
  local vault = tostring(Obsidian.dir)
  if lookup_cache.vault ~= vault or lookup_cache.reference_lookup == nil or lookup_cache.absolute_lookup == nil then
    local notes = collect_workspace_notes()
    local reference_lookup, absolute_lookup = build_note_lookups(notes)
    lookup_cache.vault = vault
    lookup_cache.reference_lookup = reference_lookup
    lookup_cache.absolute_lookup = absolute_lookup
  end

  return lookup_cache.reference_lookup, lookup_cache.absolute_lookup
end

---@param opts? { source_path: obsidian.Path|string|?, text: string|?, use_cache: boolean|? }
---@return obsidian.analysis.DeadLinkEntry[]
M.collect = function(opts)
  opts = opts or {}

  local use_cache = opts.use_cache ~= false
  local reference_lookup, absolute_lookup

  if use_cache then
    reference_lookup, absolute_lookup = get_note_lookups()
  else
    local notes = collect_workspace_notes()
    reference_lookup, absolute_lookup = build_note_lookups(notes)
  end

  if opts.source_path and opts.text then
    local source_path = Path.new(opts.source_path)
    return collect_dead_links_from_text(source_path, opts.text, reference_lookup, absolute_lookup)
  end

  if opts.source_path then
    local source_path = Path.new(opts.source_path)
    local text = read_source_text(source_path)
    return collect_dead_links_from_text(source_path, text, reference_lookup, absolute_lookup)
  end

  local notes = collect_workspace_notes()
  ---@type obsidian.analysis.DeadLinkEntry[]
  local entries = {}

  for _, note in ipairs(notes) do
    local text = table.concat(note.contents or {}, "\n")
    vim.list_extend(entries, collect_dead_links_from_text(note.path, text, reference_lookup, absolute_lookup))
  end

  table.sort(entries, function(a, b)
    if a.filename == b.filename then
      if a.line == b.line then
        return a.start < b.start
      end
      return a.line < b.line
    end
    return a.filename < b.filename
  end)

  return entries
end

M.invalidate_cache = function()
  lookup_cache.vault = nil
  lookup_cache.reference_lookup = nil
  lookup_cache.absolute_lookup = nil
end

return M
