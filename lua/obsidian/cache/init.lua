--- Obsidian cache: ORM-style repository over swappable backend.
---
--- v1 ships JSON backend + notes repository CRUD only (no query layer).
--- Wired to LSP `workspace/didChangeWatchedFiles` events for live updates.

local log = require "obsidian.log"
local watchfiles = require "obsidian.lsp.watchfiles"
local cache_note = require "obsidian.cache.note"
local JsonBackend = require "obsidian.cache.json_backend"

local M = {}

---@class obsidian.cache.State
---@field backend table
---@field vault string
---@field flush_timer uv.uv_timer_t|nil
---@field unregister fun()|nil
---@field ignore_patterns string[]

---@type obsidian.cache.State?
local state = nil

local FLUSH_DEBOUNCE_MS = 2000

local function schedule_flush()
  if not state then
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
  local root = state.vault:gsub("/+$", "")
  local rel = abs_path
  if vim.startswith(abs_path, root .. "/") then
    rel = abs_path:sub(#root + 2)
  end
  for _, pat in ipairs(state.ignore_patterns) do
    if rel:find(pat) then
      return true
    end
  end
  return false
end

---@param abs_path string
local function reindex_one(abs_path)
  if not state then
    return
  end
  if not vim.endswith(abs_path, ".md") then
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
  if not vim.endswith(new_path, ".md") then
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
  state.backend:rename(old_path, new_path, row)
  schedule_flush()
end

---@param events table[]
local function on_events(events)
  for _, ev in ipairs(events) do
    if ev.type == "created" or ev.type == "changed" then
      reindex_one(ev.path)
    elseif ev.type == "deleted" then
      remove_one(ev.path)
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
    if not name:match "%.md$" then
      return false
    end
    return not is_ignored(dir .. "/" .. name)
  end, { type = "file", path = state.vault, limit = math.huge })

  for _, abs in ipairs(files) do
    if is_ignored(abs) then
      goto skip_root
    end
    found[abs] = true
    local existing = state.backend:get(abs)
    local stat = vim.uv.fs_stat(abs)
    if not stat then
      goto continue
    end
    if force or not existing or existing.mtime ~= stat.mtime.sec or existing.size ~= stat.size then
      reindex_one(abs)
    end
    ::continue::
    ::skip_root::
  end

  for path, _ in pairs(state.backend:all()) do
    if not found[path] then
      remove_one(path)
    end
  end
end

---@class obsidian.cache.SetupOpts
---@field enabled? boolean
---@field path? string  cache file path (relative to vault or absolute)
---@field backend? string  "json" (default)
---@field ignore_patterns? string[]  Lua patterns matched against rel_path; merged with defaults via tbl_override list_field

---@param opts obsidian.cache.SetupOpts
function M.setup(opts)
  opts = opts or {}
  if opts.enabled == false then
    return
  end

  local vault = tostring(Obsidian.dir)
  local cache_path = opts.path or ".cache.json"
  if not vim.startswith(cache_path, "/") then
    cache_path = vault .. "/" .. cache_path
  end

  local ignore_patterns = vim.deepcopy(opts.ignore_patterns or {})

  local backend
  if opts.backend == nil or opts.backend == "json" then
    backend = JsonBackend.open { path = cache_path, vault = vault }
  else
    error("cache: unknown backend '" .. tostring(opts.backend) .. "'")
  end

  state = {
    backend = backend,
    vault = vault,
    flush_timer = nil,
    unregister = nil,
    ignore_patterns = ignore_patterns,
  }

  state.unregister = watchfiles.register_handler(function(events)
    on_events(events)
  end)

  vim.schedule(function()
    initial_scan(false)
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
      state.backend:close()
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
  if state and state.backend then
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
