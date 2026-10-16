local fs_util = require "obsidian.util.fs"
local api = require "obsidian.api"
local note_matcher = require "obsidian.search.note_matcher"
local SearchOpts = require "obsidian.search.opts"
local unresolved = require "obsidian.search.unresolved"
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

---@param term string
---@param dir string
---@return obsidian.search.Unresolved[] notes
---@return obsidian.search.Unresolved[] attachments
local function find_unresolved(term, dir)
  local cache = require "obsidian.cache"
  local notes = {}
  for path, row in pairs(cache.notes.all()) do
    notes[#notes + 1] = {
      path = path,
      aliases = row.aliases,
      links = row.links_out,
      searchable = not path_is_template(path, dir),
    }
  end
  local attachments = vim.tbl_keys(cache.attachments.all())
  return unresolved.collect(term, {
    root = vim.fs.normalize(tostring(Obsidian.dir)),
    scope = dir,
    notes = notes,
    attachments = attachments,
  })
end

---Find existing cached notes using the same structured domains as search.find_notes().
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.Note[] notes
---@return obsidian.search.Unresolved[]? unresolved
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
  local ignore_case = opts.ignore_case
  if ignore_case == nil then
    ignore_case = SearchOpts.should_ignore_case(term)
  end

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
    if ok and (not parse_file or note_matcher.matches(path, root, note, term, opts.match, ignore_case)) then
      notes[#notes + 1] = note
    elseif not ok then
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
  local missing
  if opts.include_unresolved then
    missing = find_unresolved(term, dir)
  end
  return notes, missing
end

---Find existing cached attachments.
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return string[] paths
---@return obsidian.search.Unresolved[]? unresolved
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
    if
      fs_util.is_subpath(path, dir)
      and not path_is_template(path, dir)
      and (query == "" or haystack:find(query, 1, true))
    then
      paths[#paths + 1] = path
    end
  end
  sort_cached_paths(paths, rows, backend_opts)
  local missing
  if opts.include_unresolved then
    _, missing = find_unresolved(term, dir)
  end
  return paths, missing
end

return M
