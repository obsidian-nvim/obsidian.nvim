local fs_util = require "obsidian.util.fs"

local M = {}

local DAY = 24 * 60 * 60
local VISIT_COOLDOWN = 30
local MAX_VISITS = 100
local HISTORY_DAYS = 90
local FLUSH_DEBOUNCE_MS = 2000

---@class obsidian.frecency.Store
---@field vault string
---@field path string
---@field visits table<string, integer[]>
---@field timer uv.uv_timer_t|nil
---@field dirty boolean

---@type table<string, obsidian.frecency.Store>
local stores = {}

---@param path string
---@return string
local function normalize_path(path)
  return tostring(require("obsidian.path").new(path):resolve())
end

---@param vault string
---@return string
local function normalize_vault(vault)
  return vim.fs.normalize(vault)
end

---@param vault string
---@return string
local function store_path(vault)
  local root = vim.fs.joinpath(
    vim.fn.stdpath "cache",
    "obsidian.nvim",
    vim.fn.sha256(vault):sub(1, 16)
  )
  return vim.fs.joinpath(root, "frecency.json")
end

---@param path string
---@param vault string
---@return obsidian.frecency.Store
local function load_store(path, vault)
  local visits = {}
  local file = io.open(path, "r")
  if file then
    local raw = file:read "*a"
    file:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    if
      ok
      and type(decoded) == "table"
      and decoded.version == 1
      and decoded.vault == vault
      and type(decoded.visits) == "table"
    then
      local cutoff = os.time() - HISTORY_DAYS * DAY
      for note_path, timestamps in pairs(decoded.visits) do
        if
          type(note_path) == "string"
          and fs_util.is_subpath(normalize_path(note_path), vault)
          and type(timestamps) == "table"
        then
          local retained = {}
          for _, timestamp in ipairs(timestamps) do
            if type(timestamp) == "number" and timestamp % 1 == 0 and timestamp >= cutoff then
              retained[#retained + 1] = timestamp
            end
          end
          while #retained > MAX_VISITS do
            table.remove(retained, 1)
          end
          if #retained > 0 then
            visits[normalize_path(note_path)] = retained
          end
        end
      end
    end
  end

  return {
    vault = vault,
    path = path,
    visits = visits,
    timer = nil,
    dirty = false,
  }
end

---@param vault string
---@return obsidian.frecency.Store
local function get_store(vault)
  vault = normalize_vault(vault)
  if not stores[vault] then
    stores[vault] = load_store(store_path(vault), vault)
  end
  return stores[vault]
end

---@param store obsidian.frecency.Store
local function flush(store)
  if not store.dirty then
    return
  end

  local root = vim.fs.dirname(store.path)
  vim.fn.mkdir(root, "p")
  fs_util.atomic_write(store.path, vim.json.encode {
    version = 1,
    vault = store.vault,
    visits = store.visits,
  })
  store.dirty = false
end

---@param store obsidian.frecency.Store
local function schedule_flush(store)
  if store.timer then
    store.timer:stop()
    store.timer:close()
  end
  store.timer = vim.uv.new_timer()
  assert(store.timer, "failed to create frecency flush timer"):start(FLUSH_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    local timer = store.timer
    store.timer = nil
    if timer then
      timer:close()
    end
    local ok, err = pcall(flush, store)
    if not ok then
      require("obsidian.log").err("[frecency] flush failed: %s", err)
    end
  end))
end

---@param visits integer[]
---@param now integer
---@return integer score
---@return integer last_visit
local function score_visits(visits, now)
  local score = 0
  local last_visit = 0
  for _, timestamp in ipairs(visits) do
    local age = math.max(0, now - timestamp)
    if age < HISTORY_DAYS * DAY then
      if age < DAY then
        score = score + 100
      elseif age < 7 * DAY then
        score = score + 70
      elseif age < 30 * DAY then
        score = score + 30
      else
        score = score + 10
      end
      last_visit = math.max(last_visit, timestamp)
    end
  end
  return score, last_visit
end

---@param path string
---@param vault string
---@param now integer?
---@return boolean recorded
function M.record(path, vault, now)
  vault = normalize_vault(vault)
  path = normalize_path(path)
  if not fs_util.is_subpath(path, vault) then
    return false
  end

  now = now or os.time()
  local store = get_store(vault)
  local visits = store.visits[path] or {}
  local last_visit = visits[#visits]
  if last_visit and now - last_visit < VISIT_COOLDOWN then
    return false
  end

  local retained = {}
  for _, timestamp in ipairs(visits) do
    if now - timestamp < HISTORY_DAYS * DAY then
      retained[#retained + 1] = timestamp
    end
  end
  retained[#retained + 1] = now
  while #retained > MAX_VISITS do
    table.remove(retained, 1)
  end

  store.visits[path] = retained
  store.dirty = true
  schedule_flush(store)
  return true
end

---@param path string
---@param vault string
---@param now integer?
---@return integer score
---@return integer last_visit
function M.score(path, vault, now)
  local store = get_store(vault)
  return score_visits(store.visits[normalize_path(path)] or {}, now or os.time())
end

---@param vault string
---@param reversed boolean?
---@param now integer?
---@return fun(a: string, b: string): boolean
function M.comparator(vault, reversed, now)
  local scores = {}
  local function score(path)
    if not scores[path] then
      scores[path] = { M.score(path, vault, now) }
    end
    return unpack(scores[path])
  end

  return function(a, b)
    local a_score, a_last_visit = score(a)
    local b_score, b_last_visit = score(b)
    if a_score ~= b_score then
      return reversed ~= false and a_score > b_score or reversed == false and a_score < b_score
    elseif a_last_visit ~= b_last_visit then
      return reversed ~= false and a_last_visit > b_last_visit or reversed == false and a_last_visit < b_last_visit
    end

    return normalize_path(a):lower() < normalize_path(b):lower()
  end
end

---@param paths string[]
---@param vault string
---@param reversed boolean?
---@return string[]
function M.sort_paths(paths, vault, reversed)
  table.sort(paths, M.comparator(vault, reversed))
  return paths
end

---@param path string
---@param vault string
M._load_store = load_store

---@param store obsidian.frecency.Store
M._flush = flush

---@param visits integer[]
---@param now integer
M._score_visits = score_visits

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("obsidian-frecency-flush", { clear = true }),
  callback = function()
    for _, store in pairs(stores) do
      if store.timer then
        store.timer:stop()
        store.timer:close()
        store.timer = nil
      end
      local ok, err = pcall(flush, store)
      if not ok then
        require("obsidian.log").err("[frecency] flush failed: %s", err)
      end
    end
  end,
})

return M
