--- Process-local derived caches.
---
--- Unlike `obsidian.cache`, values owned by this module are never serialized.
--- The two cache shapes here centralize the lifecycle rules shared by lazy
--- vault indexes and values derived from loaded buffers.
local watchfiles = require "obsidian.lsp.watchfiles"

local M = {}
local vault_indexes = {}
local buffer_caches = {}

local function same(a, b)
  return a == b or vim.deep_equal(a, b)
end

---@class obsidian.cache.volatile.VaultIndexSpec
---@field build fun(context: any, done: fun(value: any?, err: any?)): fun()? Build a complete value, optionally returning a cancellation function.
---@field update? fun(value: any, events: table[], context: any): boolean Incrementally update a ready value. Return false to invalidate it.
---@field matches? fun(key: string, events: table[], context: any): boolean Whether file events concern an entry.
---@field version? fun(context: any): any External dependency token. A changed token invalidates the entry.
---@field max_entries? integer Maximum number of scoped values retained by this index.

---@class obsidian.cache.volatile.VaultIndex
---@field _spec obsidian.cache.volatile.VaultIndexSpec
---@field _entries table<string, table>
---@field _unregister fun()?
---@field _max_entries integer
---@field _serial integer
local VaultIndex = {}
VaultIndex.__index = VaultIndex

---@param entry table
---@param value any?
---@param err any?
local function finish_waiters(entry, value, err)
  local waiters = entry.waiters
  entry.waiters = {}
  for _, waiter in ipairs(waiters) do
    local callback = waiter.callback
    if vim.in_fast_event() then
      vim.schedule(function()
        callback(value, err)
      end)
    else
      callback(value, err)
    end
  end
end

---@param self obsidian.cache.volatile.VaultIndex
---@param key string
---@param entry table
local function start_build(self, key, entry)
  if entry.status == "building" then
    return
  end
  entry.status = "building"
  entry.serial = entry.serial + 1
  local serial = entry.serial
  local context = entry.context
  local settled = false

  local function done(value, err)
    if settled then
      return
    end
    settled = true
    if self._entries[key] ~= entry or entry.serial ~= serial then
      return
    end
    entry.cancel = nil
    if err ~= nil or value == nil then
      entry.status = "cold"
      entry.value = nil
      finish_waiters(entry, nil, err or "vault index build returned no value")
      return
    end
    entry.status = "ready"
    entry.value = value
    finish_waiters(entry, value, nil)
  end

  local ok, cancel_or_err = pcall(self._spec.build, context, done)
  if not ok then
    done(nil, cancel_or_err)
  elseif type(cancel_or_err) == "function" and entry.status == "building" and entry.serial == serial then
    entry.cancel = cancel_or_err
  end
end

---@param self obsidian.cache.volatile.VaultIndex
---@param keep_key string
local function prune_vault_entries(self, keep_key)
  while vim.tbl_count(self._entries) > self._max_entries do
    local oldest_key, oldest_used
    for candidate_key, candidate in pairs(self._entries) do
      if
        candidate_key ~= keep_key
        and candidate.status ~= "building"
        and (oldest_used == nil or candidate.used < oldest_used)
      then
        oldest_key, oldest_used = candidate_key, candidate.used
      end
    end
    if not oldest_key then
      return
    end
    self._entries[oldest_key] = nil
  end
end

---@param key string
---@param context any
---@param callback fun(value: any?, err: any?)
function VaultIndex:get(key, context, callback)
  key = tostring(key)
  local entry = self._entries[key]
  local version = self._spec.version and self._spec.version(context) or nil
  if not entry then
    entry = {
      status = "cold",
      value = nil,
      context = context,
      version = version,
      waiters = {},
      serial = 0,
      cancel = nil,
      used = self._serial,
    }
    self._serial = self._serial + 1
    self._entries[key] = entry
    prune_vault_entries(self, key)
  else
    -- The latest request carries the current workspace/configuration context.
    entry.context = context
    if self._spec.version and not same(entry.version, version) then
      entry.version = version
      self:invalidate(key)
    end
  end

  entry.used = self._serial
  self._serial = self._serial + 1
  if entry.status == "ready" then
    callback(entry.value, nil)
    return
  end

  entry.waiters[#entry.waiters + 1] = { callback = callback }
  start_build(self, key, entry)
end

---@param key string
---@return any?
function VaultIndex:peek(key)
  local entry = self._entries[tostring(key)]
  return entry and entry.status == "ready" and entry.value or nil
end

---@param key string
---@param opts { restart: boolean? }|?
function VaultIndex:invalidate(key, opts)
  opts = opts or {}
  key = tostring(key)
  local entry = self._entries[key]
  if not entry then
    return
  end
  entry.serial = entry.serial + 1
  if entry.cancel then
    pcall(entry.cancel)
    entry.cancel = nil
  end
  entry.status = "cold"
  entry.value = nil
  if opts.restart ~= false and #entry.waiters > 0 then
    start_build(self, key, entry)
  elseif #entry.waiters > 0 then
    finish_waiters(entry, nil, "vault index invalidated")
  end
end

---@param events table[]
function VaultIndex:handle(events)
  for key, entry in pairs(self._entries) do
    local matches = not self._spec.matches or self._spec.matches(key, events, entry.context)
    if matches then
      if entry.status == "ready" and self._spec.update then
        local ok, handled = pcall(self._spec.update, entry.value, events, entry.context)
        if not ok or handled == false then
          self:invalidate(key)
        end
      else
        self:invalidate(key)
      end
    end
  end
end

---@param keep_key string?
function VaultIndex:clear(keep_key)
  keep_key = keep_key and tostring(keep_key) or nil
  for key, entry in pairs(self._entries) do
    if key ~= keep_key then
      entry.serial = entry.serial + 1
      if entry.cancel then
        pcall(entry.cancel)
      end
      finish_waiters(entry, nil, "vault index cleared")
      self._entries[key] = nil
    end
  end
end

function VaultIndex:dispose()
  self:clear()
  if self._unregister then
    self._unregister()
    self._unregister = nil
  end
  for i, index in ipairs(vault_indexes) do
    if index == self then
      table.remove(vault_indexes, i)
      break
    end
  end
end

---@param spec obsidian.cache.volatile.VaultIndexSpec
---@return obsidian.cache.volatile.VaultIndex
function M.vault_index(spec)
  assert(type(spec) == "table" and type(spec.build) == "function", "volatile vault index requires build()")
  local index = setmetatable({
    _spec = spec,
    _entries = {},
    _unregister = nil,
    _max_entries = spec.max_entries or 8,
    _serial = 1,
  }, VaultIndex)
  if spec.matches or spec.update then
    index._unregister = watchfiles.register_handler(function(events)
      index:handle(events)
    end)
  end
  vault_indexes[#vault_indexes + 1] = index
  return index
end

---@class obsidian.cache.volatile.BufferValues
---@field _entries table<integer, table<string, table>>
---@field _attached table<integer, boolean>
---@field _max_entries integer
local BufferValues = {}
BufferValues.__index = BufferValues

---@param self obsidian.cache.volatile.BufferValues
---@param bufnr integer
local function attach_buffer(self, bufnr)
  if self._attached[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  self._attached[bufnr] = vim.api.nvim_buf_attach(bufnr, false, {
    on_reload = function(_, reloaded)
      self:invalidate(reloaded)
    end,
    on_detach = function(_, detached)
      self._entries[detached] = nil
      self._attached[detached] = nil
    end,
  })
end

---@param bufnr integer
---@param key string
---@param version { epoch: any, revision: any }
---@param opts { allow_stale: boolean? }|?
---@return any?
function BufferValues:get(bufnr, key, version, opts)
  opts = opts or {}
  local entries = self._entries[bufnr]
  local entry = entries and entries[key] or nil
  if not entry or not same(entry.epoch, version.epoch) then
    return nil
  end
  if not opts.allow_stale and not same(entry.revision, version.revision) then
    return nil
  end
  entry.used = self._serial
  self._serial = self._serial + 1
  return entry.value
end

---@param bufnr integer
---@param key string
---@param version { epoch: any, revision: any }
---@param value any
function BufferValues:set(bufnr, key, version, value)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  attach_buffer(self, bufnr)
  local entries = self._entries[bufnr]
  if not entries then
    entries = {}
    self._entries[bufnr] = entries
  end
  entries[key] = {
    epoch = version.epoch,
    revision = version.revision,
    value = value,
    used = self._serial,
  }
  self._serial = self._serial + 1

  local count = vim.tbl_count(entries)
  while count > self._max_entries do
    local oldest_key, oldest_used
    for candidate_key, entry in pairs(entries) do
      if candidate_key ~= key and (oldest_used == nil or entry.used < oldest_used) then
        oldest_key, oldest_used = candidate_key, entry.used
      end
    end
    if not oldest_key then
      break
    end
    entries[oldest_key] = nil
    count = count - 1
  end
end

---@param bufnr integer?
function BufferValues:invalidate(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if bufnr then
    self._entries[bufnr] = nil
  else
    self._entries = {}
  end
end

function BufferValues:clear()
  self._entries = {}
end

---@param opts { max_entries_per_buffer: integer? }|?
---@return obsidian.cache.volatile.BufferValues
function M.buffer_values(opts)
  opts = opts or {}
  local cache = setmetatable({
    _entries = {},
    _attached = {},
    _max_entries = opts.max_entries_per_buffer or 16,
    _serial = 1,
  }, BufferValues)
  buffer_caches[#buffer_caches + 1] = cache
  return cache
end

---Reset process-local state after workspace options change. Vault indexes are
---keyed by root and may stay warm while another configured workspace is active;
---callers can explicitly clear them when reconfiguring the same root.
---@param opts { vaults: boolean? }|?
function M.reset_workspace(opts)
  opts = opts or {}
  if opts.vaults then
    for _, index in ipairs(vault_indexes) do
      index:clear()
    end
  end
  for _, cache in ipairs(buffer_caches) do
    cache:clear()
  end
end

---Test/shutdown helper.
function M.clear()
  M.reset_workspace { vaults = true }
end

return M
