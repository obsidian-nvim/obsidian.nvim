--- Obsidian cache: ORM-style repository over swappable backend.
---
--- v1 ships JSON backend + notes repository CRUD only (no query layer).
--- Wired to LSP `workspace/didChangeWatchedFiles` events for live updates.

local log = require "obsidian.log"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache_note = require "obsidian.cache.note"
local ignore = require "obsidian.ignore"
local filetypes = require "obsidian.filetypes"

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

---@type obsidian.cache.State?
local state = nil

local FLUSH_DEBOUNCE_MS = 2000
---@param path string
---@return "note"|"attachment"|nil
local function file_kind(path)
  if filetypes.is_note(path) then
    return "note"
  elseif filetypes.is_attachment(path) then
    return "attachment"
  end
end

---@param abs_path string
---@return boolean
local function is_internal(abs_path)
  if not state then
    return true
  end
  local rel = abs_path
  local root = state.vault:gsub("/+$", "")
  if vim.startswith(abs_path, root .. "/") then
    rel = abs_path:sub(#root + 2)
  end
  local first = rel:match "^([^/]+)"
  local opts = Obsidian.opts or {}
  local config_dir = opts.sync and opts.sync.config_dir or ".obsidian"
  return first == config_dir or first == ".git"
end

---@param abs_path string
---@param kind "note"|"attachment"
---@return table?
local function build_row(abs_path, kind)
  local current_state = assert(state, "cache not initialized")
  if kind == "note" then
    local row = cache_note.build(abs_path, current_state.vault)
    if row then
      row.kind = "note"
    end
    return row
  end

  local stat = vim.uv.fs_stat(abs_path)
  if not stat or stat.type ~= "file" then
    return nil
  end
  return {
    kind = "attachment",
    mtime = stat.mtime.sec,
    size = stat.size,
  }
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
  local kind = file_kind(abs_path)
  if not kind then
    return
  end
  if is_internal(abs_path) or is_ignored(abs_path) then
    return
  end
  local row = build_row(abs_path, kind)
  if row then
    state.backend:put(abs_path, row)
    schedule_flush()
  end
end

---@param abs_path string
local function remove_one(abs_path)
  if not state then
    return
  end
  state.backend:delete(vim.fs.normalize(abs_path))
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
  local kind = file_kind(new_path)
  if not kind or is_internal(new_path) or is_ignored(new_path) then
    state.backend:delete(old_path)
    schedule_flush()
    return
  end
  local row = build_row(new_path, kind)
  if not row then
    state.backend:delete(old_path)
    schedule_flush()
    return
  end
  state.backend:delete(old_path)
  state.backend:put(new_path, row)
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

---Walk vault, populate cache for supported notes and attachments.
---Skips entries whose mtime/size match.
---@param force boolean? rebuild every entry regardless of stat
local function initial_scan(force)
  if not state then
    return
  end
  local scan_state = state
  local found = {}
  local files = vim.fs.find(function(name, dir)
    if not file_kind(name) then
      return false
    end
    local path = dir .. "/" .. name
    return not is_internal(path) and not is_ignored(path)
  end, { type = "file", path = scan_state.vault, limit = math.huge })

  for _, abs in ipairs(files) do
    if not is_ignored(abs) then
      abs = vim.fs.normalize(abs)
      found[abs] = true
      local existing = scan_state.backend:get(abs)
      local stat = vim.uv.fs_stat(abs)
      if stat and (force or not existing or existing.mtime ~= stat.mtime.sec or existing.size ~= stat.size) then
        reindex_one(abs)
      end
    end
  end

  for path, _ in pairs(scan_state.backend:all()) do
    local normalized = vim.fs.normalize(path)
    if not found[normalized] then
      scan_state.backend:delete(path)
      schedule_flush()
    end
  end
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
    return fn()
  end
  if state.ready then
    return fn()
  end
  state.pending[#state.pending + 1] = fn
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

---@param row table?
---@return boolean
local function is_note_row(row)
  -- Rows written before the typed cache are notes.
  return row ~= nil and (row.kind == nil or row.kind == "note")
end

---@param row table?
---@return boolean
local function is_attachment_row(row)
  return row ~= nil and row.kind == "attachment"
end

---@param predicate fun(row: table?): boolean
---@return table<string, table>
local function filter_rows(predicate)
  assert(state, "cache not initialized")
  local rows = {}
  for path, row in pairs(state.backend:all()) do
    if predicate(row) then
      rows[path] = row
    end
  end
  return rows
end

---@param predicate fun(row: table?): boolean
---@return integer
local function count_rows(predicate)
  if not state then
    return 0
  end
  local count = 0
  for _, row in pairs(state.backend:all()) do
    if predicate(row) then
      count = count + 1
    end
  end
  return count
end

---@param path string
---@return string
local function rel_path(path)
  assert(state, "cache not initialized")
  local root = state.vault:gsub("/+$", "")
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

---@param path string  absolute path
---@return table
function M.notes.get(path)
  assert(state, "cache not initialized")
  local row = state.backend:get(vim.fs.normalize(path))
  if not is_note_row(row) then
    error("cache: no note at " .. path)
  end
  ---@cast row -nil
  return row
end

---@param path string
---@return table?
function M.notes.find(path)
  if not state then
    return nil
  end
  local row = state.backend:get(vim.fs.normalize(path))
  return is_note_row(row) and row or nil
end

---@return table<string, table>
function M.notes.all()
  assert(state, "cache not initialized")
  return filter_rows(is_note_row)
end

---@return integer
function M.notes.count()
  return count_rows(is_note_row)
end

---@param path string
---@return string
function M.notes.rel_path(path)
  return rel_path(path)
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
  row.kind = "note"
  state.backend:put(vim.fs.normalize(row.path), row)
  schedule_flush()
end

---@param path string
---@param patch table
function M.notes.update(path, patch)
  assert(state, "cache not initialized")
  path = vim.fs.normalize(path)
  local row = state.backend:get(path)
  if not is_note_row(row) then
    error("cache: no note at " .. path)
  end
  ---@cast row -nil
  for k, v in pairs(patch) do
    row[k] = v
  end
  state.backend:put(path, row)
  schedule_flush()
end

---@param path string
function M.notes.delete(path)
  if not state then
    return
  end
  state.backend:delete(vim.fs.normalize(path))
  schedule_flush()
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

-- ──────────────────────────────────────────────────────────────────────────────
-- Attachments repository (read-only)
-- ──────────────────────────────────────────────────────────────────────────────

---@class obsidian.cache.AttachmentsRepo
M.attachments = {}

---@param path string
---@return table?
function M.attachments.find(path)
  if not state then
    return nil
  end
  local row = state.backend:get(vim.fs.normalize(path))
  return is_attachment_row(row) and row or nil
end

---@return table<string, table>
function M.attachments.all()
  return filter_rows(is_attachment_row)
end

---@return integer
function M.attachments.count()
  return count_rows(is_attachment_row)
end

---@param path string
---@return string
function M.attachments.rel_path(path)
  return rel_path(path)
end

---@param path string
---@return string
function M.attachments.basename(path)
  return vim.fs.basename(path)
end

return M
