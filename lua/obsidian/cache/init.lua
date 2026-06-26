--- Obsidian cache: ORM-style repository over swappable backend.
---
--- v1 ships JSON backend + notes repository CRUD only (no query layer).
--- Wired to LSP `workspace/didChangeWatchedFiles` events for live updates.

local log = require "obsidian.log"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache_note = require "obsidian.cache.note"
local ignore = require "obsidian.ignore"

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

---@type table<string, obsidian.cache.Backend>
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
local MARKDOWN_EXTENSIONS = { md = true, markdown = true, qmd = true, base = true }

---@param path string
---@return boolean
local function is_markdown_note(path)
  local ext = (path:match "%.([^./]+)$" or ""):lower()
  return MARKDOWN_EXTENSIONS[ext] == true
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
  state.flush_timer:start(
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
  if not is_markdown_note(abs_path) then
    return
  end
  if is_ignored(abs_path) then
    return
  end
  local row = cache_note.build(abs_path, state.vault)
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
  state.backend:delete(abs_path)
  schedule_flush()
end

---@param old_path string
---@param new_path string
local function rename_one(old_path, new_path)
  if not state then
    return
  end
  if not is_markdown_note(new_path) then
    state.backend:delete(old_path)
    schedule_flush()
    return
  end
  local row = cache_note.build(new_path, state.vault)
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
    return ev.path
  elseif ev.uri then
    return vim.uri_to_fname(ev.uri)
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

---Walk vault, populate cache for all `.md` files. Skips notes whose mtime/size match.
---@param force boolean? rebuild every entry regardless of stat
local function initial_scan(force)
  local found = {}
  local files = vim.fs.find(function(name, dir)
    if not is_markdown_note(name) then
      return false
    end
    return not is_ignored(dir .. "/" .. name)
  end, { type = "file", path = state.vault, limit = math.huge })

  for _, abs in ipairs(files) do
    if not is_ignored(abs) then
      found[abs] = true
      local existing = state.backend:get(abs)
      local stat = vim.uv.fs_stat(abs)
      if stat and (force or not existing or existing.mtime ~= stat.mtime.sec or existing.size ~= stat.size) then
        reindex_one(abs)
      end
    end
  end

  for path, _ in pairs(state.backend:all()) do
    if not found[path] then
      remove_one(path)
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
  return backends[name or "json"]
end

---@class obsidian.cache.SetupOpts
---@field enabled? boolean
---@field backend? string

---@param opts obsidian.cache.SetupOpts
function M.setup(opts)
  opts = opts or {}
  if opts.enabled == false then
    return
  end

  local vault = vim.fs.normalize(tostring(Obsidian.dir))
  local cache_dir = vim.fs.joinpath(vim.fn.stdpath "cache", "obsidian.nvim")
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

  vim.schedule(function()
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
  assert(state, "cache not initialized")
  local row = state.backend:get(path)
  if not row then
    error("cache: no note at " .. path)
  end
  return row
end

---@param path string
---@return table?
function M.notes.find(path)
  if not state then
    return nil
  end
  return state.backend:get(path)
end

---@return table<string, table>
function M.notes.all()
  assert(state, "cache not initialized")
  return state.backend:all()
end

---@return integer
function M.notes.count()
  if not state then
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
  state.backend:put(row.path, row)
  schedule_flush()
end

---@param path string
---@param patch table
function M.notes.update(path, patch)
  assert(state, "cache not initialized")
  local row = state.backend:get(path)
  if not row then
    error("cache: no note at " .. path)
  end
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
  state.backend:delete(path)
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

return M
