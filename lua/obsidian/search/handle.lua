local M = {}

---@class obsidian.search.AsyncHandle
---@field cancel fun(self: obsidian.search.AsyncHandle)
---@field kill fun(self: obsidian.search.AsyncHandle, signal: integer|string|?) Compatibility with vim.SystemObj.

---Create a uniform handle for asynchronous search operations.
---@param cancel fun()|?
---@return obsidian.search.AsyncHandle
M.new = function(cancel)
  local cancelled = false
  local function stop()
    if cancelled then
      return
    end
    cancelled = true
    if cancel then
      cancel()
    end
  end
  return {
    cancel = function()
      stop()
    end,
    kill = function()
      stop()
    end,
  }
end

---@return obsidian.search.AsyncHandle
M.noop = function()
  return M.new()
end

---@param handle any
M.cancel = function(handle)
  if type(handle) == "function" then
    handle()
  elseif type(handle) == "table" then
    if type(handle.cancel) == "function" then
      handle:cancel()
    elseif type(handle.kill) == "function" then
      handle:kill(15)
    end
  end
end

return M
