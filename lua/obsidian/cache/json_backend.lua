local util = require "obsidian.util"

---@class obsidian.cache.JsonBackend
---@field path string
---@field data table
---@field dirty boolean
local M = {}
M.__index = M

local SCHEMA_VERSION = 2
local INDEXER_VERSION = 1

M.SCHEMA_VERSION = SCHEMA_VERSION
M.INDEXER_VERSION = INDEXER_VERSION

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read "*a"
  f:close()
  return s
end

---@param opts { path: string, vault: string }
function M.open(opts)
  local self = setmetatable({}, M)
  self.path = opts.path
  self.dirty = false

  local raw = read_file(opts.path)
  local parsed
  if raw and #raw > 0 then
    local ok, decoded = pcall(vim.json.decode, raw)
    if
      ok
      and type(decoded) == "table"
      and decoded.schema_version == SCHEMA_VERSION
      and decoded.indexer_version == INDEXER_VERSION
      and decoded.vault == opts.vault
      and type(decoded.entries) == "table"
    then
      parsed = decoded
    end
  end

  self.data = parsed
    or {
      schema_version = SCHEMA_VERSION,
      indexer_version = INDEXER_VERSION,
      vault = opts.vault,
      generated_at = os.time(),
      entries = {},
    }
  if raw and not parsed then
    self.dirty = true
  end
  self.data.vault = opts.vault
  return self
end

---@param key string  primary key (absolute path)
function M:get(key)
  return self.data.entries[key]
end

---@return table<string, table>
function M:all()
  return self.data.entries
end

---@param key string
---@param row table
function M:put(key, row)
  self.data.entries[key] = row
  self.dirty = true
end

---@param key string
function M:delete(key)
  if self.data.entries[key] ~= nil then
    self.data.entries[key] = nil
    self.dirty = true
  end
end

function M:flush()
  if not self.dirty then
    return
  end
  self.data.generated_at = os.time()
  local encoded = vim.json.encode(self.data)
  util.atomic_write(self.path, encoded)
  self.dirty = false
end

function M:close()
  self:flush()
end

return M
