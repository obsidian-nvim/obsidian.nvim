---@class obsidian.cache.MemoryBackend
---@field data table<string, table>
local M = {}
M.__index = M

---@param _opts { vault: string }
function M.open(_opts)
  local self = setmetatable({}, M)
  self.data = {}
  return self
end

---@param key string
function M:get(key)
  return self.data[key]
end

---@return table<string, table>
function M:all()
  return self.data
end

---@param key string
---@param row table
function M:put(key, row)
  self.data[key] = row
end

---@param key string
function M:delete(key)
  self.data[key] = nil
end

function M.flush() end

function M:close()
  self.data = {}
end

return M
