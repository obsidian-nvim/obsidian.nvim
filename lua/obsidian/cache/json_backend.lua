---@class obsidian.cache.JsonBackend
---@field path string
---@field data table
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

local function atomic_write(path, contents)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    error("cache: cannot open " .. tmp .. ": " .. tostring(err))
  end
  f:write(contents)
  f:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then
    error("cache: rename failed: " .. tostring(rerr))
  end
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
function M:get(key)
  return self.data.notes[key]
end

---@return table<string, table>
function M:all()
  return self.data.notes
end

---@param key string
---@param row table
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
  atomic_write(self.path, encoded)
  self.dirty = false
end

function M:close()
  self:flush()
end

return M
