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

---@param event table
---@return table
local function normalize_event(event)
  local normalized = vim.tbl_extend("force", {}, event)
  if normalized.uri then
    normalized.path = vim.fs.normalize(vim.uri_to_fname(normalized.uri))
  elseif normalized.path then
    normalized.path = vim.fs.normalize(normalized.path)
  end
  if normalized.old_uri then
    normalized.old_path = vim.fs.normalize(vim.uri_to_fname(normalized.old_uri))
  elseif normalized.old_path then
    normalized.old_path = vim.fs.normalize(normalized.old_path)
  end
  if normalized.new_uri then
    normalized.new_path = vim.fs.normalize(vim.uri_to_fname(normalized.new_uri))
  elseif normalized.new_path then
    normalized.new_path = vim.fs.normalize(normalized.new_path)
  end
  return normalized
end

---@param events lsp.FileEvent[]
---@return lsp.FileEvent[]
M.handle = function(events)
  local normalized_events = {}
  for i, event in ipairs(events) do
    normalized_events[i] = normalize_event(event)
  end

  if #handlers == 0 then
    return normalized_events
  end

  local active_handlers = {}
  for i, handler in ipairs(handlers) do
    active_handlers[i] = handler
  end

  for _, handler in ipairs(active_handlers) do
    util.fire_callback("watchfiles", handler, normalized_events, events)
  end

  return normalized_events
end

return M
