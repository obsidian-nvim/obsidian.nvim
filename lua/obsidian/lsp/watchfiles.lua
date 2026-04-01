local util = require "obsidian.util"

local M = {}

local FileChangeType = vim.lsp.protocol.FileChangeType

local handlers = {}

local event_names = {
  [FileChangeType.Created] = "created",
  [FileChangeType.Changed] = "changed",
  [FileChangeType.Deleted] = "deleted",
}

local function build_change_event(change, index)
  local event_type = event_names[change.type]
  if not event_type then
    return nil
  end

  return {
    type = event_type,
    path = vim.uri_to_fname(change.uri),
    uri = change.uri,
    index = index,
  }
end

local function sort_by_index(events)
  table.sort(events, function(a, b)
    return a.index < b.index
  end)

  for _, event in ipairs(events) do
    event.index = nil
  end

  return events
end

local function dispatch(callback_name, events, payload, source)
  if #handlers == 0 then
    vim.print(events)
    return events
  end

  for _, handler in ipairs(handlers) do
    util.fire_callback(callback_name, handler, events, payload, source)
  end

  return events
end

---@param changes lsp.FileEvent[]
---@return table[]
M.normalize = function(changes)
  local normalized = {}

  for index, change in ipairs(changes) do
    local event = build_change_event(change, index)
    if event then
      normalized[#normalized + 1] = event
    end
  end

  return sort_by_index(normalized)
end

---@param handler fun(events: table[], payload: table[], source: string)
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

---@param changes lsp.FileEvent[]
---@return table[]
M.handle = function(changes)
  local events = M.normalize(changes)
  return dispatch("watchfiles", events, changes, "workspace/didChangeWatchedFiles")
end

return M
