---@class obsidian.cache.MemoryBackend : obsidian.cache.Store, obsidian.cache.Backend
---@field data table<string, obsidian.cache.NoteRow>
local M = {}
M.__index = M

---@param _opts obsidian.cache.OpenOpts
---@return obsidian.cache.MemoryBackend
function M.open(_opts)
  local self = setmetatable({}, M)
  self.data = {}
  return self
end

---@param key string
---@return obsidian.cache.NoteRow?
function M:get(key)
  return self.data[key]
end

---@return table<string, obsidian.cache.NoteRow>
function M:all()
  return self.data
end

---@param key string
---@param row obsidian.cache.NoteRow
function M:put(key, row)
  self.data[key] = row
end

---@param key string
function M:delete(key)
  self.data[key] = nil
end

function M:flush() end

function M:close()
  self.data = {}
end

return M
