local fs_util = require "obsidian.util.fs"
local attachment = require "obsidian.attachment"
local link = require "obsidian.link"
local api = require "obsidian.api"
local note_matcher = require "obsidian.search.note_matcher"
local SearchOpts = require "obsidian.search.opts"
local log = require "obsidian.log"

local M = {}

---@param path string
---@param dir string
---@return boolean
local function path_is_template(path, dir)
  local workspace = api.find_workspace(dir)
  local templates_dir = workspace and api.templates_dir(workspace) or nil
  return templates_dir ~= nil and fs_util.is_subpath(path, tostring(templates_dir))
end

---@param paths string[]
---@param rows table<string, table>
---@param opts obsidian.search.BackendOpts
local function sort_cached_paths(paths, rows, opts)
  if opts.sort_by == false then
    return
  end
  local sort_by = opts.sort_by or "path"
  local reversed = opts.sort_reversed or false
  table.sort(paths, function(a, b)
    ---@type string|number
    local av = a
    ---@type string|number
    local bv = b
    if sort_by == "modified" then
      local a_stat, b_stat = rows[a].stat or {}, rows[b].stat or {}
      av = (a_stat.mtime_sec or 0) * 1000000000 + (a_stat.mtime_nsec or 0)
      bv = (b_stat.mtime_sec or 0) * 1000000000 + (b_stat.mtime_nsec or 0)
    elseif sort_by == "accessed" or sort_by == "created" then
      local stat_key = sort_by == "accessed" and "atime" or "birthtime"
      local a_stat, b_stat = vim.uv.fs_stat(a), vim.uv.fs_stat(b)
      av = a_stat and a_stat[stat_key] and a_stat[stat_key].sec or 0
      bv = b_stat and b_stat[stat_key] and b_stat[stat_key].sec or 0
    end
    if av == bv then
      return a < b
    elseif reversed then
      return av > bv
    else
      return av < bv
    end
  end)
end

---Find existing cached notes using the same structured domains as search.find_notes().
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.Note[]
M.find_notes = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local backend_opts = SearchOpts.resolve(dir, {
    sort_by = opts.sort_by,
    sort_reversed = opts.sort_reversed,
  })
  local root = vim.fs.normalize(tostring(Obsidian.dir))
  local rows = cache.notes.all()
  local paths = {}
  local ignore_case = SearchOpts.should_ignore_case(term)

  for path, row in pairs(rows) do
    if
      fs_util.is_subpath(path, dir)
      and not path_is_template(path, dir)
      and note_matcher.matches(path, root, row, term, opts.match, ignore_case)
    then
      paths[#paths + 1] = path
    end
  end
  sort_cached_paths(paths, rows, backend_opts)

  local Note = require "obsidian.note"
  local parse_opts = note_matcher.parse_opts(opts)
  local parse_file = parse_opts.collect_sections
    or parse_opts.collect_anchor_links
    or parse_opts.collect_blocks
    or parse_opts.collect_block_candidates
  local notes = {}
  local first_err, first_err_path
  local err_count = 0
  for _, path in ipairs(paths) do
    local ok, note
    if parse_file then
      ok, note = pcall(Note.from_file, path, parse_opts)
    else
      ok, note = pcall(Note.from_cache, path, rows[path])
    end
    if ok then
      notes[#notes + 1] = note
    else
      err_count = err_count + 1
      if not first_err then
        first_err, first_err_path = note, path
      end
    end
  end
  if first_err then
    log.err(
      "%d error(s) occurred during cached note search. First error from '%s':\n%s",
      err_count,
      first_err_path,
      first_err
    )
  end
  return notes
end

---Find existing cached attachments.
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return string[]
M.find_attachments = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local backend_opts = SearchOpts.resolve(dir, {
    sort_by = opts.sort_by,
    sort_reversed = opts.sort_reversed,
  })
  local root = vim.fs.normalize(tostring(Obsidian.dir))
  local query = vim.trim(term or "")
  local ignore_case = SearchOpts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end
  local rows = cache.attachments.all()
  local paths = {}
  for path in pairs(rows) do
    local rel = fs_util.relpath(root, path) or path
    local haystack = rel
    if ignore_case then
      haystack = haystack:lower()
    end
    if fs_util.is_subpath(path, dir) and (query == "" or haystack:find(query, 1, true)) then
      paths[#paths + 1] = path
    end
  end
  sort_cached_paths(paths, rows, backend_opts)
  return paths
end

---@param target string?
---@return boolean
local function is_external_target(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param lookup table<string, boolean>
local function add_lookup_path(path, lookup)
  local cache = require "obsidian.cache"
  local path_no_ext = path:gsub("%.md$", "")
  local rel_path = cache.notes.rel_path(path)
  local rel_path_no_ext = rel_path:gsub("%.md$", "")
  local basename = vim.fn.fnamemodify(path, ":t")
  for _, key in ipairs {
    path,
    path_no_ext,
    rel_path,
    rel_path_no_ext,
    basename,
    vim.fn.fnamemodify(path, ":t:r"),
  } do
    lookup[key:lower()] = true
  end
end

---@param target string
---@param lookup table<string, boolean>
---@param source_path string
---@return boolean
local function target_exists(target, lookup, source_path)
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  local candidates
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    local absolute = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded))
    local absolute_no_ext = absolute:gsub("%.md$", "")
    candidates = { absolute, absolute_no_ext, absolute .. ".md" }
  else
    local normalized = normalize_link_target(target)
    local normalized_no_ext = normalized:gsub("%.md$", "")
    candidates = { normalized, normalized_no_ext, normalized .. ".md" }
  end

  for _, key in ipairs(candidates) do
    if lookup[key:lower()] then
      return true
    end
  end
  return false
end

---@param target string
---@param source_path string
---@param target_path string
---@param is_attachment boolean
---@return string
local function missing_entry_key(target, source_path, target_path, is_attachment)
  if is_attachment then
    return target_path:lower()
  end

  local decoded = vim.uri_decode(target):gsub("\\", "/")
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded)):lower()
  end
  return normalize_link_target(decoded):lower()
end

---Find note, attachment, and unresolved-link references from the cache.
---The cache must be ready before calling this function. Tags are reserved for a
---future cache-powered reference kind.
---@param term string
---@param opts obsidian.search.FindRefsOpts|?
---@return obsidian.Ref[]
M.find_refs = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local include_notes = opts.include_notes ~= false
  local include_attachments = opts.include_attachments == true
  local include_unresolved = opts.include_unresolved == true
  -- TODO: honor opts.include_tags once tags are exposed as cache-powered references.
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local query = vim.trim(term or "")
  local ignore_case = SearchOpts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end
  local notes = cache.notes.all()
  local attachments = cache.attachments.all()
  local lookup = {}
  ---@type obsidian.Ref[]
  local refs = {}
  ---@type table<string, obsidian.Ref>
  local unresolved = {}

  ---@param ref obsidian.Ref
  ---@return obsidian.Ref?
  local function add_ref(ref)
    local text = ignore_case and ref.text:lower() or ref.text
    if query ~= "" and not text:find(query, 1, true) then
      return
    end
    refs[#refs + 1] = ref
    return ref
  end

  for path, row in pairs(notes) do
    add_lookup_path(path, lookup)
    for _, alias in ipairs(row.aliases or {}) do
      lookup[alias:lower()] = true
    end
  end
  for path in pairs(attachments) do
    add_lookup_path(path, lookup)
  end

  local Note = require "obsidian.note"
  if include_notes then
    for path, row in pairs(notes) do
      if fs_util.is_subpath(path, dir) and not path_is_template(path, dir) then
        local text = note_matcher.without_note_extension(cache.notes.rel_path(path))
        local note = Note.from_cache(path, row)
        add_ref { kind = "note", text = text, path = path, note = note, attachment = false }
        for _, alias in ipairs(row.aliases or {}) do
          add_ref {
            kind = "note",
            text = text .. " | " .. alias,
            path = path,
            note = note,
            attachment = false,
          }
        end
      end
    end
  end

  if include_attachments then
    for path in pairs(attachments) do
      if fs_util.is_subpath(path, dir) then
        add_ref {
          kind = "attachment",
          text = cache.attachments.rel_path(path),
          path = path,
          attachment = true,
        }
      end
    end
  end

  if include_unresolved then
    for source_path, row in pairs(notes) do
      if not path_is_template(source_path, dir) then
        for _, outgoing in ipairs(row.links_out or {}) do
          local target = outgoing.target
          if not is_external_target(target) and not target_exists(target, lookup, source_path) then
            local target_is_attachment = attachment.is_attachment_path(target:lower())
            if include_attachments or not target_is_attachment then
              local target_path = link.missing_link_path(target, source_path)
              if target_path and fs_util.is_subpath(target_path, dir) then
                local key = missing_entry_key(target, source_path, target_path, target_is_attachment)
                ---@type obsidian.NoteCreationReference
                local reference = {
                  filename = source_path,
                  lnum = outgoing.line or 1,
                  col = outgoing.col or 1,
                  raw = outgoing.raw or target,
                }
                local existing = unresolved[key]
                if existing then
                  local references = assert(existing.references, "unresolved reference locations are missing")
                  references[#references + 1] = reference
                else
                  local ref = {
                    kind = "unresolved",
                    text = normalize_link_target(target),
                    path = target_path,
                    target = vim.uri_decode(target):gsub("\\", "/"),
                    attachment = target_is_attachment,
                    references = { reference },
                  }
                  if add_ref(ref) then
                    unresolved[key] = ref
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  table.sort(refs, function(a, b)
    if a.text ~= b.text then
      return a.text < b.text
    end
    return (a.path or "") < (b.path or "")
  end)
  return refs
end

return M
