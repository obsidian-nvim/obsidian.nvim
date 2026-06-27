local util = require "obsidian.util"

---@class obsidian.cache.JsonData
---@field version integer
---@field vault string
---@field generated_at integer
---@field notes table<string, obsidian.cache.NoteRow>

---@class obsidian.cache.JsonBackend : obsidian.cache.Store, obsidian.cache.Backend
---@field path string
---@field data obsidian.cache.JsonData
---@field dirty boolean
local M = {}
M.__index = M

local SCHEMA_VERSION = 1

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read "*a"
  f:close()
  return s
end

---@param opts obsidian.cache.OpenOpts
---@return obsidian.cache.JsonBackend
function M.open(opts)
  local self = setmetatable({}, M)
  self.path = opts.path
  self.dirty = false

  local raw = read_file(opts.path)
  ---@type obsidian.cache.JsonData?
  local parsed
  if raw and #raw > 0 then
    local ok, decoded = pcall(vim.json.decode, raw)
    if ok and type(decoded) == "table" and decoded.version == SCHEMA_VERSION then
      parsed = decoded
    end
  end

  self.data = parsed
    or {
      version = SCHEMA_VERSION,
      vault = opts.vault,
      generated_at = os.time(),
      notes = {},
    }
  self.data.vault = opts.vault
  return self
end

---@param key string  primary key (absolute path)
---@return obsidian.cache.NoteRow?
function M:get(key)
  return self.data.notes[key]
end

---@return table<string, obsidian.cache.NoteRow>
function M:all()
  return self.data.notes
end

---@param key string
---@param row obsidian.cache.NoteRow
function M:put(key, row)
  self.data.notes[key] = row
  self.dirty = true
end

---@param key string
function M:delete(key)
  if self.data.notes[key] ~= nil then
    self.data.notes[key] = nil
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
