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

---@param old_key string
---@param new_key string
---@param patch table?
function M:rename(old_key, new_key, patch)
  local row = self.data[old_key]
  if not row then
    return
  end
  self.data[old_key] = nil
  if patch then
    for k, v in pairs(patch) do
      row[k] = v
    end
  end
  self.data[new_key] = row
end

function M:flush() end

function M:close()
  self.data = {}
end

return M
