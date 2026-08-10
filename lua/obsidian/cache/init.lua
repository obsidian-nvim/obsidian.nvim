--- Obsidian cache: ORM-style repository over swappable backend.
---
--- v1 ships JSON backend + notes repository CRUD only (no query layer).
--- Wired to LSP document-save and watched-file events for live updates.

local log = require "obsidian.log"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache_note = require "obsidian.cache.note"
local ignore = require "obsidian.ignore"
local search_files = require "obsidian.search.files"

local M = {}

---@class obsidian.cache.Backend
---@field open fun(opts: table): obsidian.cache.Store

---@class obsidian.cache.Store
---@field close fun(self: obsidian.cache.Store)?
---@field flush fun(self: obsidian.cache.Store)?
---@field get fun(self: obsidian.cache.Store, key: string): table?
---@field all fun(self: obsidian.cache.Store): table<string, table>
---@field put fun(self: obsidian.cache.Store, key: string, row: table)
---@field delete fun(self: obsidian.cache.Store, key: string)

---@type table<string, any>
local backends = {
  json = require "obsidian.cache.json_backend",
  memory = require "obsidian.cache.memory_backend",
}

---@class obsidian.cache.State
---@field backend obsidian.cache.Store
---@field vault string
---@field flush_timer uv.uv_timer_t|nil
---@field unregister fun()|nil
---@field ready boolean
---@field pending fun()[]
---@field generation integer
---@field symbol_index obsidian.cache.SymbolIndex

---@type obsidian.cache.State?
local state = nil

local FLUSH_DEBOUNCE_MS = 2000
---@class obsidian.cache.SymbolIndex
---@field by_path table<string, table>
---@field by_key table<string, string[]>
---@field keys_by_path table<string, string[]>

local function empty_symbol_index()
  return { by_path = {}, by_key = {}, keys_by_path = {} }
end

---@param path string
---@param row table
---@return table
local function symbol_entry(path, row)
  return {
    path = path,
    relative_path = row.relative_path,
    basename = row.basename,
    filename = row.filename,
    extension = row.extension,
    id = row.id,
    title = row.title,
    aliases = vim.deepcopy(row.aliases or {}),
  }
end

---@param path string
local function remove_symbol(path)
  if not state then
    return
  end
  local index = state.symbol_index
  for _, key in ipairs(index.keys_by_path[path] or {}) do
    local paths = index.by_key[key]
    if paths then
      for i = #paths, 1, -1 do
        if paths[i] == path then
          table.remove(paths, i)
        end
      end
      if #paths == 0 then
        index.by_key[key] = nil
      end
    end
  end
  index.keys_by_path[path] = nil
  index.by_path[path] = nil
end

---@param path string
---@param row table
local function add_symbol(path, row)
  if not state then
    return
  end
  remove_symbol(path)
  local entry = symbol_entry(path, row)
  state.symbol_index.by_path[path] = entry

  local seen = {}
  local keys = {}
  local function add(value)
    value = value and tostring(value) or nil
    if not value or value == "" then
      return
    end
    local key = value:lower()
    if seen[key] then
      return
    end
    seen[key] = true
    keys[#keys + 1] = key
    local paths = state.symbol_index.by_key[key] or {}
    paths[#paths + 1] = path
    table.sort(paths, function(a, b)
      return a:lower() < b:lower()
    end)
    state.symbol_index.by_key[key] = paths
  end

  add(row.relative_path)
  if row.relative_path then
    add(row.relative_path:gsub("%.[^./]+$", ""))
  end
  add(row.basename)
  add(row.id)
  add(row.title)
  for _, alias in ipairs(row.aliases or {}) do
    add(alias)
  end
  state.symbol_index.keys_by_path[path] = keys
end

local function rebuild_symbol_index()
  if not state then
    return
  end
  state.symbol_index = empty_symbol_index()
  for path, row in pairs(state.backend:all()) do
    add_symbol(vim.fs.normalize(path), row)
  end
end

---@param path string
---@param row table
local function put_row(path, row)
  if not state then
    return
  end
  path = vim.fs.normalize(path)
  state.backend:put(path, row)
  add_symbol(path, row)
  state.generation = state.generation + 1
end

---@param path string
local function delete_row(path)
  if not state then
    return
  end
  path = vim.fs.normalize(path)
  state.backend:delete(path)
  remove_symbol(path)
  state.generation = state.generation + 1
end

---@param abs_path string
---@return boolean
local function is_in_vault(abs_path)
  if not state then
    return false
  end
  local root = state.vault:gsub("/+$", "")
  return abs_path == root or vim.startswith(abs_path, root .. "/")
end

local function schedule_flush()
  if not state or not state.backend.flush then
    return
  end
  if state.flush_timer then
    state.flush_timer:stop()
    state.flush_timer:close()
  end
  state.flush_timer = vim.uv.new_timer()
  assert(state.flush_timer, "failed to create cache flush timer"):start(
    FLUSH_DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      if state and state.backend then
        local ok, err = pcall(function()
          state.backend:flush()
        end)
        if not ok then
          log.err("[cache] flush failed: %s", err)
        end
      end
    end)
  )
end

---@param abs_path string
---@return boolean
local function is_ignored(abs_path)
  if not state then
    return true
  end
  -- TODO: if users need cache-specific ignore behavior, add an option to override
  -- this. For now cache follows the global file.ignore_filters path.
  return ignore.is_ignored(abs_path)
end

---@param abs_path string
local function reindex_one(abs_path)
  if not state then
    return
  end
  abs_path = vim.fs.normalize(abs_path)
  if not is_in_vault(abs_path) then
    return
  end
  if not search_files.is_searchable(abs_path) or is_ignored(abs_path) then
    delete_row(abs_path)
    schedule_flush()
    return
  end
  local row = cache_note.build(abs_path, state.vault)
  if row then
    put_row(abs_path, row)
  else
    -- A missing or malformed file must not leave structured data from an older
    -- version of the file visible through the cache.
    delete_row(abs_path)
  end
  schedule_flush()
end

---@param abs_path string
local function remove_one(abs_path)
  if not state then
    return
  end
  delete_row(abs_path)
  schedule_flush()
end

---@param old_path string
---@param new_path string
local function rename_one(old_path, new_path)
  if not state then
    return
  end
  old_path = vim.fs.normalize(old_path)
  new_path = vim.fs.normalize(new_path)
  if not search_files.is_searchable(new_path) or is_ignored(new_path) then
    delete_row(old_path)
    schedule_flush()
    return
  end
  local row = cache_note.build(new_path, state.vault)
  if not row then
    delete_row(old_path)
    schedule_flush()
    return
  end
  delete_row(old_path)
  put_row(new_path, row)
  schedule_flush()
end

---@param ev table
---@return string?
local function event_path(ev)
  if ev.path then
    return vim.fs.normalize(ev.path)
  elseif ev.uri then
    return vim.fs.normalize(vim.uri_to_fname(ev.uri))
  end
end

---@param events table[]
local function on_events(events)
  local FileChangeType = vim.lsp.protocol.FileChangeType
  for _, ev in ipairs(events) do
    local path = event_path(ev)
    if
      ev.type == "created"
      or ev.type == "changed"
      or ev.type == FileChangeType.Created
      or ev.type == FileChangeType.Changed
    then
      if path then
        reindex_one(path)
      end
    elseif ev.type == "deleted" or ev.type == FileChangeType.Deleted then
      if path then
        remove_one(path)
      end
    elseif ev.type == "renamed" then
      rename_one(ev.old_path, ev.new_path)
    end
  end
end

---@param row table
---@param stat uv.fs_stat.result
---@return boolean
local function stat_matches(row, stat)
  return row.mtime == stat.mtime.sec and row.mtime_nsec == stat.mtime.nsec and row.size == stat.size
end

---Walk vault, populate cache for all `.md` files. Skips notes whose mtime/size match.
---@param force boolean? rebuild every entry regardless of stat
local function initial_scan(force)
  if not state then
    return
  end
  local scan_state = state
  local found = {}
  local files = vim.fs.find(function(name, dir)
    if not search_files.is_searchable(name) then
      return false
    end
    return not is_ignored(dir .. "/" .. name)
  end, { type = "file", path = scan_state.vault, limit = math.huge })

  for _, abs in ipairs(files) do
    if not is_ignored(abs) then
      abs = vim.fs.normalize(abs)
      found[abs] = true
      local existing = scan_state.backend:get(abs)
      local stat = vim.uv.fs_stat(abs)
      if stat and (force or not existing or not stat_matches(existing, stat)) then
        reindex_one(abs)
      end
    end
  end

  for path, _ in pairs(scan_state.backend:all()) do
    local normalized = vim.fs.normalize(path)
    if not found[normalized] then
      delete_row(path)
      schedule_flush()
    end
  end
  rebuild_symbol_index()
end

local function mark_ready()
  if not state then
    return
  end
  state.ready = true
  local pending = state.pending
  state.pending = {}
  for _, fn in ipairs(pending) do
    local ok, err = pcall(fn)
    if not ok then
      log.err("[cache] pending callback failed: %s", err)
    end
  end
end

---Run `fn` now if cache ready, else queue until initial scan finishes.
---@param fn fun()
function M.when_ready(fn)
  if not state then
    fn()
    return function() end
  end
  if state.ready then
    fn()
    return function() end
  end
  local cancelled = false
  state.pending[#state.pending + 1] = function()
    if not cancelled then
      fn()
    end
  end
  return function()
    cancelled = true
  end
end

---@return integer
function M.generation()
  return state and state.generation or 0
end

---@return boolean
function M.is_ready()
  return state ~= nil and state.ready
end

---@return boolean
function M.is_enabled()
  return state ~= nil
end

---Register a cache backend.
---@param name string
---@param backend obsidian.cache.Backend
function M.register_backend(name, backend)
  backends[name] = backend
end

---Alias for register_backend(), matching other backend registries.
---@param name string
---@param backend obsidian.cache.Backend
function M.register(name, backend)
  M.register_backend(name, backend)
end

---@param name string?
---@return obsidian.cache.Backend?
function M.get_backend(name)
  local backend = backends[name or "json"]
  ---@cast backend obsidian.cache.Backend?
  return backend
end

---@param opts obsidian.config.CacheOpts
function M.setup(opts)
  opts = opts or {}
  if opts.enabled == false then
    M.shutdown()
    return
  end

  M.shutdown()

  local vault = vim.fs.normalize(tostring(Obsidian.dir))
  local stdpath_cache = vim.fn.stdpath "cache"
  ---@cast stdpath_cache string
  local cache_dir = vim.fs.joinpath(stdpath_cache, "obsidian.nvim")
  vim.fn.mkdir(cache_dir, "p")
  local cache_path = vim.fs.joinpath(cache_dir, vim.fn.sha256(vault):sub(1, 16) .. ".json")

  local backend_name = opts.backend or "json"
  local backend_impl = M.get_backend(backend_name)
  if not backend_impl then
    error("cache: unknown backend '" .. tostring(backend_name) .. "'")
  end
  local backend = backend_impl.open(vim.tbl_extend("force", vim.deepcopy(opts), { path = cache_path, vault = vault }))

  state = {
    backend = backend,
    vault = vault,
    flush_timer = nil,
    unregister = nil,
    ready = false,
    pending = {},
    generation = 0,
    symbol_index = empty_symbol_index(),
  }

  state.unregister = watchfiles.register_handler(function(events)
    on_events(events)
  end)

  local setup_state = state
  vim.schedule(function()
    if state ~= setup_state then
      return
    end
    initial_scan()
    mark_ready()
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("obsidian-cache-flush", { clear = true }),
    callback = function()
      M.shutdown()
    end,
  })
end

function M.shutdown()
  if not state then
    return
  end
  if state.flush_timer then
    state.flush_timer:stop()
    state.flush_timer:close()
    state.flush_timer = nil
  end
  if state.unregister then
    state.unregister()
    state.unregister = nil
  end
  if state.backend then
    pcall(function()
      if state.backend.close then
        state.backend:close()
      end
    end)
  end
  state = nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Notes repository (CRUD)
-- ──────────────────────────────────────────────────────────────────────────────

---@class obsidian.cache.NotesRepo
M.notes = {}

---@param path string  absolute path
---@return table
function M.notes.get(path)
  assert(state and state.ready, "cache not ready")
  local row = state.backend:get(vim.fs.normalize(path))
  if not row then
    error("cache: no note at " .. path)
  end
  return vim.deepcopy(row)
end

---@param path string
---@return table?
function M.notes.find(path)
  if not state or not state.ready then
    return nil
  end
  local row = state.backend:get(vim.fs.normalize(path))
  return row and vim.deepcopy(row) or nil
end

---@return table<string, table>
function M.notes.all()
  assert(state and state.ready, "cache not ready")
  return vim.deepcopy(state.backend:all())
end

---@class obsidian.cache.NoteSnapshot
---@field vault string
---@field generation integer
---@field rows table<string, table>

---@return obsidian.cache.NoteSnapshot
function M.notes.snapshot()
  assert(state and state.ready, "cache not ready")
  local rows = {}
  for path, row in pairs(state.backend:all()) do
    rows[path] = vim.deepcopy(row)
  end
  return { vault = state.vault, generation = state.generation, rows = rows }
end

---@param path string
---@param dir string
---@return boolean
local function is_under(path, dir)
  dir = vim.fs.normalize(dir):gsub("/+$", "")
  path = vim.fs.normalize(path)
  return path == dir or vim.startswith(path, dir .. "/")
end

---@param opts table|nil
---@return table[]
function M.notes.entries(opts)
  assert(state and state.ready, "cache not ready")
  opts = opts or {}
  local entries = {}
  for path, entry in pairs(state.symbol_index.by_path) do
    local accepted = (not opts.dir or is_under(path, tostring(opts.dir)))
      and (not opts.exclude_path or vim.fs.normalize(opts.exclude_path) ~= path)
      and (not opts.extensions or opts.extensions[entry.extension] == true)
    if accepted then
      entries[#entries + 1] = vim.deepcopy(entry)
    end
  end
  table.sort(entries, function(a, b)
    return a.relative_path:lower() < b.relative_path:lower()
  end)
  return entries
end

---@param opts table|nil
---@return table[]
function M.notes.symbols(opts)
  assert(state and state.ready, "cache not ready")
  opts = opts or {}
  local query = opts.query and tostring(opts.query):lower() or nil
  if not query or query == "" then
    return M.notes.entries(opts)
  end

  local matched_paths = {}
  if opts.exact then
    for _, path in ipairs(state.symbol_index.by_key[query] or {}) do
      matched_paths[path] = true
    end
  else
    for key, paths in pairs(state.symbol_index.by_key) do
      if key:find(query, 1, true) then
        for _, path in ipairs(paths) do
          matched_paths[path] = true
        end
      end
    end
  end

  local entries = {}
  for path in pairs(matched_paths) do
    local entry = state.symbol_index.by_path[path]
    local accepted = entry
      and (not opts.dir or is_under(path, tostring(opts.dir)))
      and (not opts.exclude_path or vim.fs.normalize(opts.exclude_path) ~= path)
      and (not opts.extensions or opts.extensions[entry.extension] == true)
    if accepted then
      entries[#entries + 1] = vim.deepcopy(entry)
    end
  end
  table.sort(entries, function(a, b)
    return a.relative_path:lower() < b.relative_path:lower()
  end)
  return entries
end

---@return integer
function M.notes.count()
  if not state or not state.ready then
    return 0
  end
  local n = 0
  for _ in pairs(state.backend:all()) do
    n = n + 1
  end
  return n
end

---@param path string
---@return string
function M.notes.rel_path(path)
  assert(state, "cache not initialized")
  local root = state.vault:gsub("/+$", "")
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

---@param path string
---@return string
function M.notes.basename(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

---@param row table  must include `path`
function M.notes.upsert(row)
  assert(state, "cache not initialized")
  assert(row.path, "row.path required")
  local path = vim.fs.normalize(row.path)
  local stored = vim.deepcopy(row)
  stored.path = nil
  put_row(path, stored)
  schedule_flush()
end

---@param path string
---@param patch table
function M.notes.update(path, patch)
  assert(state, "cache not initialized")
  path = vim.fs.normalize(path)
  local row = assert(state.backend:get(path), "cache: no note at " .. path)
  row = vim.deepcopy(row)
  for k, v in pairs(patch) do
    row[k] = v
  end
  put_row(path, row)
  schedule_flush()
end

---@param path string
function M.notes.delete(path)
  if not state then
    return
  end
  delete_row(path)
  schedule_flush()
end

---Refresh one note directly from disk.
---@param path string
function M.notes.refresh(path)
  reindex_one(path)
end

---Replace a cached note path after a successful filesystem rename.
---@param old_path string
---@param new_path string
function M.notes.rename(old_path, new_path)
  rename_one(old_path, new_path)
end

---Force flush to disk (otherwise debounced).
function M.notes.flush()
  if state and state.backend and state.backend.flush then
    state.backend:flush()
  end
end

---Force full rebuild from vault.
function M.notes.reindex()
  if not state then
    return
  end
  initial_scan(true)
end

return M
