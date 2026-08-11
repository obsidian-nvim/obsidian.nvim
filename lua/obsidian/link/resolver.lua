local Path = require "obsidian.path"
local attachment = require "obsidian.attachment"
local util = require "obsidian.util"

local M = {}

local NOTE_EXTENSIONS = {
  md = true,
  markdown = true,
  qmd = true,
  base = true,
}

---@class obsidian.link.Target
---@field raw string
---@field normalized string
---@field kind "note"|"attachment"|"file"|"external"|"local_fragment"|"invalid"
---@field anchor? string
---@field raw_anchor? string
---@field block? string
---@field scheme? string
---@field vault_relative? boolean Target started with `/`.

---@class obsidian.link.ResolutionEntry
---@field kind "note"|"attachment"
---@field path string
---@field value any

---@class obsidian.link.Resolution
---@field target obsidian.link.Target
---@field status "resolved"|"missing"|"ambiguous"|"invalid"
---@field paths string[]
---@field path? string
---@field predicted_path? string
---@field entries? obsidian.link.ResolutionEntry[]
---@field notes? obsidian.Note[]

---@class obsidian.link.ResolveOpts
---@field source_path? string Absolute path of the note containing the link.
---@field vault? string|obsidian.Path
---@field index? obsidian.link.Index
---@field notes? obsidian.note.LoadOpts
---@field timeout? integer
---@field link_type? "wiki"|"markdown"

---@class obsidian.link.Index
---@field by_path table<string, obsidian.link.ResolutionEntry>
---@field by_identifier table<string, obsidian.link.ResolutionEntry[]>

---@param path string
---@return string
local function normalize_abs_path(path)
  return vim.fs.normalize(tostring(Path.new(path):resolve()))
end

---@param opts obsidian.link.ResolveOpts|?
---@return string
local function vault_path(opts)
  return vim.fs.normalize(tostring((opts and opts.vault) or Obsidian.dir))
end

---@param path string
---@param opts obsidian.link.ResolveOpts|?
---@return string?
local function path_in_vault(path, opts)
  local normalized = normalize_abs_path(path)
  if util.is_subpath(normalized, vault_path(opts)) then
    return normalized
  end
end

---@param path string
---@return string
function M.extension(path)
  return (path:match "%.([^./\\]+)$" or ""):lower()
end

---@param path string
---@return boolean
function M.is_note_path(path)
  return NOTE_EXTENSIONS[M.extension(path)] == true
end

---@param target string
---@return string
function M.normalize_target(target)
  target = vim.trim(vim.uri_decode(target)):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param raw string
---@param opts { link_type: "wiki"|"markdown"|nil }|?
---@return obsidian.link.Target
function M.parse_target(raw, opts)
  raw = type(raw) == "string" and vim.trim(raw) or ""
  if raw == "" then
    return { raw = raw, normalized = "", kind = "invalid" }
  end

  local decoded = vim.uri_decode(raw)
  local is_uri, scheme = util.is_uri(decoded)
  if is_uri then
    return {
      raw = raw,
      normalized = decoded,
      kind = "external",
      scheme = scheme,
    }
  end

  local target, block = util.strip_block_links(decoded)
  local raw_anchor
  target, _, raw_anchor = util.strip_anchor_links(target)
  local anchor = raw_anchor and util.standardize_anchor(raw_anchor) or nil
  local vault_relative = vim.startswith(target:gsub("\\", "/"), "/")
  target = M.normalize_target(target)

  if target == "" then
    if anchor or block then
      return {
        raw = raw,
        normalized = target,
        kind = "local_fragment",
        anchor = anchor,
        raw_anchor = raw_anchor,
        block = block,
      }
    end
    return { raw = raw, normalized = target, kind = "invalid" }
  end

  local lower = target:lower()
  local kind
  if attachment.is_attachment_path(lower) then
    kind = "attachment"
  elseif M.is_note_path(lower) or M.extension(lower) == "" or not opts or opts.link_type ~= "markdown" then
    -- Unknown suffixes are valid in wiki note IDs (for example
    -- `[[release.v2]]`). Existing files are reclassified during path lookup.
    kind = "note"
  else
    kind = "file"
  end

  return {
    raw = raw,
    normalized = target,
    kind = kind,
    anchor = anchor,
    raw_anchor = raw_anchor,
    block = block,
    vault_relative = vault_relative,
  }
end

---@param target string
---@return string
local function note_filename(target)
  if M.is_note_path(target) then
    return target
  end
  return target .. ".md"
end

---@param candidates string[]
---@param seen table<string, boolean>
---@param path string|obsidian.Path|?
---@param opts obsidian.link.ResolveOpts|?
local function add_candidate(candidates, seen, path, opts)
  if not path then
    return
  end
  local normalized = path_in_vault(tostring(path), opts)
  if normalized and not seen[normalized] then
    seen[normalized] = true
    candidates[#candidates + 1] = normalized
  end
end

---@param target obsidian.link.Target
---@param opts obsidian.link.ResolveOpts|?
---@return string[]
function M.path_candidates(target, opts)
  opts = opts or {}
  if target.kind == "external" or target.kind == "local_fragment" or target.kind == "invalid" then
    return {}
  end

  local vault = Path.new(vault_path(opts))
  local source_dir = opts.source_path and opts.source_path ~= "" and Path.new(vim.fs.dirname(opts.source_path)) or nil
  local candidates, seen = {}, {}

  if target.kind == "attachment" then
    local location = target.normalized
    if location:find("/", 1, true) or target.vault_relative then
      if source_dir and not target.vault_relative then
        add_candidate(candidates, seen, source_dir / location, opts)
      end
      add_candidate(candidates, seen, vault / location, opts)
    else
      local folder = assert(Obsidian.opts.attachments.folder, "attachments.folder is required")
      if vim.startswith(folder, ".") then
        add_candidate(candidates, seen, (source_dir or vault) / folder / location, opts)
      else
        add_candidate(candidates, seen, vault / folder / location, opts)
      end
    end
    return candidates
  end

  local locations = { target.normalized }
  if target.kind == "note" and not M.is_note_path(target.normalized) then
    locations[#locations + 1] = note_filename(target.normalized)
  end

  local function add_at(base)
    for _, location in ipairs(locations) do
      add_candidate(candidates, seen, base / location, opts)
    end
  end

  if source_dir and not target.vault_relative then
    add_at(source_dir)
  end

  if not target.vault_relative then
    -- Preserve the old cwd fallback, but never allow it to escape the vault.
    for _, location in ipairs(locations) do
      add_candidate(candidates, seen, Path.new(location), opts)
    end
  end
  add_at(vault)

  if target.kind == "note" then
    if Obsidian.opts.notes_subdir ~= nil then
      add_at(vault / Obsidian.opts.notes_subdir)
    end
    if Obsidian.opts.daily_notes.folder ~= nil then
      add_at(vault / Obsidian.opts.daily_notes.folder)
    end
  end

  return candidates
end

---@param target obsidian.link.Target
---@param opts obsidian.link.ResolveOpts|?
---@return string?
function M.predict_path(target, opts)
  opts = opts or {}
  if target.kind == "note" and target.vault_relative then
    return path_in_vault(tostring(Path.new(vault_path(opts)) / note_filename(target.normalized)), opts)
  elseif target.kind == "note" and not M.is_note_path(target.normalized) then
    local Note = require "obsidian.note"
    local note_opts = { id = target.normalized }
    if
      opts.source_path
      and Obsidian.opts.new_notes_location == "current_dir"
      and not target.normalized:find("/", 1, true)
    then
      note_opts.dir = vim.fs.dirname(opts.source_path)
    end
    local path = Note.resolve_creation_path(note_opts)
    return path_in_vault(tostring(path), opts)
  end

  return M.path_candidates(target, opts)[1]
end

---@param target obsidian.link.Target
---@param status "resolved"|"missing"|"ambiguous"|"invalid"
---@param entries obsidian.link.ResolutionEntry[]|?
---@param opts obsidian.link.ResolveOpts|?
---@return obsidian.link.Resolution
local function resolution(target, status, entries, opts)
  entries = entries or {}
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)

  local paths, notes = {}, {}
  for _, entry in ipairs(entries) do
    paths[#paths + 1] = entry.path
    if entry.kind == "note" and type(entry.value) == "table" and entry.value._location then
      notes[#notes + 1] = entry.value
    end
  end

  local result = {
    target = target,
    status = status,
    paths = paths,
    entries = entries,
  }
  if #notes > 0 then
    result.notes = notes
  end
  if #paths > 0 then
    result.path = paths[1]
  elseif status == "missing" then
    result.predicted_path = M.predict_path(target, opts)
  end
  return result
end

---@param identifier string
---@param kind "note"|"attachment"
---@return string[]
function M.identifier_keys(identifier, kind)
  local normalized = M.normalize_target(identifier):lower()
  if normalized == "" then
    return {}
  end

  local keys = { normalized }
  if kind == "note" and M.is_note_path(normalized) then
    keys[#keys + 1] = normalized:gsub("%.[^./]+$", "")
  end
  return util.tbl_unique(keys)
end

---@return obsidian.link.Index
function M.new_index()
  return { by_path = {}, by_identifier = {} }
end

---@param index obsidian.link.Index
---@param identifier string
---@param entry obsidian.link.ResolutionEntry
local function index_identifier(index, identifier, entry)
  for _, key in ipairs(M.identifier_keys(identifier, entry.kind)) do
    local entries = index.by_identifier[key]
    if not entries then
      entries = {}
      index.by_identifier[key] = entries
    end
    if not vim.tbl_contains(entries, entry) then
      entries[#entries + 1] = entry
    end
  end
end

---@param index obsidian.link.Index
---@param kind "note"|"attachment"
---@param path string
---@param value any
---@param identifiers string[]|?
function M.index_entry(index, kind, path, value, identifiers)
  path = vim.fs.normalize(path)
  local entry = { kind = kind, path = path, value = value }
  index.by_path[path] = entry

  local vault = vault_path()
  local rel_path = util.is_subpath(path, vault) and path:sub(#vault:gsub("/+$", "") + 2) or path
  index_identifier(index, rel_path, entry)
  index_identifier(index, vim.fs.basename(path), entry)
  if kind == "note" then
    index_identifier(index, vim.fn.fnamemodify(path, ":t:r"), entry)
  end
  for _, identifier in ipairs(identifiers or {}) do
    index_identifier(index, identifier, entry)
  end
end

---@param notes table<string, table>|obsidian.Note[]
---@param attachments table<string, table>|?
---@return obsidian.link.Index
function M.build_index(notes, attachments)
  local index = M.new_index()
  if vim.islist(notes) then
    for _, note in ipairs(notes) do
      if note.path then
        M.index_entry(index, "note", tostring(note.path), note, note:reference_ids())
      end
    end
  else
    for path, row in pairs(notes or {}) do
      local identifiers = vim.list_extend(vim.deepcopy(row.aliases or {}), vim.deepcopy(row.reference_ids or {}))
      M.index_entry(index, "note", path, row, identifiers)
    end
  end
  for path, row in pairs(attachments or {}) do
    M.index_entry(index, "attachment", path, row)
  end
  return index
end

---@param target obsidian.link.Target
---@param opts obsidian.link.ResolveOpts|?
---@return obsidian.link.Resolution
function M.resolve_from_index(target, opts)
  opts = opts or {}
  local index = opts.index or M.new_index()

  if target.kind == "invalid" then
    return resolution(target, "invalid", nil, opts)
  elseif target.kind == "external" or target.kind == "local_fragment" then
    return resolution(target, "resolved", nil, opts)
  end

  for _, candidate in ipairs(M.path_candidates(target, opts)) do
    local indexed = index.by_path[candidate]
    local stat = vim.uv.fs_stat(candidate)
    if indexed then
      return resolution(target, "resolved", { indexed }, opts)
    elseif stat then
      local resolved_target = target
      local existing_kind = target.kind
      if stat.type ~= "directory" and target.kind == "note" and not M.is_note_path(candidate) then
        resolved_target = vim.tbl_extend("force", {}, target, { kind = "file" })
        existing_kind = "file"
      end
      ---@type obsidian.link.ResolutionEntry?
      local entry
      if stat.type ~= "directory" and existing_kind ~= "file" then
        entry = { kind = existing_kind, path = candidate, value = nil }
      end
      local result = resolution(resolved_target, "resolved", entry and { entry } or nil, opts)
      result.path = candidate
      result.paths = { candidate }
      return result
    end
  end

  if target.kind == "note" or target.kind == "attachment" then
    local found, seen = {}, {}
    for _, key in ipairs(M.identifier_keys(target.normalized, target.kind)) do
      for _, entry in ipairs(index.by_identifier[key] or {}) do
        local implicit_base = target.kind == "note"
          and M.extension(entry.path) == "base"
          and M.extension(target.normalized) ~= "base"
        if entry.kind == target.kind and not implicit_base and not seen[entry.path] then
          found[#found + 1] = entry
          seen[entry.path] = true
        end
      end
    end
    if #found == 1 then
      return resolution(target, "resolved", found, opts)
    elseif #found > 1 then
      return resolution(target, "ambiguous", found, opts)
    end
  end

  return resolution(target, "missing", nil, opts)
end

return M
