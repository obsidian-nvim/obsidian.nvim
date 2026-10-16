local fs_util = require "obsidian.util.fs"
local api = require "obsidian.api"
local note_matcher = require "obsidian.search.note_matcher"
local SearchOpts = require "obsidian.search.opts"
local unresolved = require "obsidian.search.unresolved"
local log = require "obsidian.log"

local M = {}

local DEFAULT_MAX_LINES = 500

---@return integer
local function search_max_lines()
  local configured = Obsidian and Obsidian.opts and Obsidian.opts.search and Obsidian.opts.search.max_lines
  return configured or DEFAULT_MAX_LINES
end

---@param values string[]
---@param seen table<string, boolean>
---@param value string?
local function add_unique(values, seen, value)
  value = vim.trim(value or "")
  if value ~= "" and not seen[value] then
    values[#values + 1] = value
    seen[value] = true
  end
end

---@param row obsidian.cache.RangeRow
---@return obsidian.cache.RangeRow
local function copy_range(row)
  return {
    start_row = row.start_row,
    start_col = row.start_col,
    end_row = row.end_row,
    end_col = row.end_col,
  }
end

---@param row obsidian.cache.NoteRow
---@return obsidian.cache.NoteRow
local function limit_structured_row(row)
  local max_lines = search_max_lines()
  if max_lines == math.huge then
    return row
  end

  ---@type obsidian.cache.NoteRow
  local limited = vim.tbl_extend("force", {}, row)
  limited.headings = vim.tbl_filter(function(heading)
    return heading.line <= max_lines
  end, row.headings or {})

  do
    ---@type obsidian.cache.SectionRow[]
    local candidates = {}
    local candidate_indexes = {}
    for old_idx, candidate in ipairs(row.block_candidates or {}) do
      if candidate.range.start_row < max_lines then
        ---@type obsidian.cache.SectionRow
        local copy = {
          header = candidate.header,
          level = candidate.level,
          anchor = candidate.anchor,
          range = copy_range(candidate.range),
          heading_range = copy_range(candidate.heading_range),
          content_range = copy_range(candidate.content_range),
          block_type = candidate.block_type,
          line = candidate.line,
        }
        local line_count = max_lines - candidate.range.start_row
        if candidate.contents then
          copy.contents = vim.list_slice(candidate.contents, 1, line_count)
        end
        copy.range.end_row = math.min(copy.range.end_row, max_lines)
        copy.content_range.end_row = math.min(copy.content_range.end_row, max_lines)
        candidates[#candidates + 1] = copy
        candidate_indexes[old_idx] = #candidates
      end
    end
    limited.block_candidates = candidates

    ---@type table<string, obsidian.cache.BlockRow>
    local blocks = {}
    for id, block in pairs(row.blocks or {}) do
      if block.line <= max_lines and (not block.candidate or candidate_indexes[block.candidate]) then
        local copy = vim.deepcopy(block)
        copy.candidate = copy.candidate and candidate_indexes[copy.candidate] or nil
        blocks[id] = copy
      end
    end
    limited.blocks = blocks

    local blocks_search = {}
    local seen = {}
    for id, block in pairs(blocks) do
      add_unique(blocks_search, seen, id)
      add_unique(blocks_search, seen, block.block)
    end
    for _, candidate in ipairs(candidates) do
      add_unique(blocks_search, seen, table.concat(candidate.contents or {}, "\n"))
    end
    limited.blocks_search = blocks_search
  end
  return limited
end

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
---@param opts obsidian.search.FindNotesBackendOpts|?
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

  local selected_rows = {}
  local structured_domain = opts.domain == "headings" or opts.domain == "blocks"
  for path, row in pairs(rows) do
    if fs_util.is_subpath(path, dir) and not path_is_template(path, dir) then
      local selected = structured_domain and limit_structured_row(row) or row
      if note_matcher.matches(path, root, selected, term, opts.domain, ignore_case) then
        paths[#paths + 1] = path
        selected_rows[path] = selected
      end
    end
  end
  sort_cached_paths(paths, rows, backend_opts)

  local Note = require "obsidian.note"
  local notes = {}
  local first_err, first_err_path
  local err_count = 0
  for _, path in ipairs(paths) do
    local ok, note = pcall(Note.from_cache, path, selected_rows[path], search_max_lines())
    if ok then
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
