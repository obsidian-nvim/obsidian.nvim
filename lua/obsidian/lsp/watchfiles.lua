local util = require "obsidian.util"

local M = {}

local handlers = {}

---@param handler fun(events: lsp.FileEvent[], raw_changes: lsp.FileEvent[])
---@return fun()
M.register_handler = function(handler)
  handlers[#handlers + 1] = handler

  return function()
    for i, fn in ipairs(handlers) do
      if fn == handler then
        table.remove(handlers, i)
        break
      end
    end
  end
end

M.reset_handlers = function()
  handlers = {}
end

---@param events lsp.FileEvent[]
---@return lsp.FileEvent[]
M.handle = function(events)
  if #handlers > 0 then
    local active_handlers = {}
    for i, handler in ipairs(handlers) do
      active_handlers[i] = handler
    end

    for _, handler in ipairs(active_handlers) do
      util.fire_callback("watchfiles", handler, events, events)
    end
  end

  local graph = package.loaded["obsidian.core-plugins.graph"]
  if type(graph) == "table" and type(graph.handle_watchfiles) == "function" then
    util.fire_callback("watchfiles.graph", graph.handle_watchfiles, events, events)
  end

  return events
end

return M
