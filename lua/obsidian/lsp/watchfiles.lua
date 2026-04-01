local util = require "obsidian.util"

local M = {}

local FileChangeType = vim.lsp.protocol.FileChangeType

local handlers = {}

local event_names = {
  [FileChangeType.Created] = "created",
  [FileChangeType.Changed] = "changed",
  [FileChangeType.Deleted] = "deleted",
}

local function path_ext(path)
  return vim.fn.fnamemodify(path, ":e")
end

local function build_event(change, index)
  local event_type = event_names[change.type]
  if not event_type then
    return nil
  end

  local path = vim.uri_to_fname(change.uri)

  return {
    type = event_type,
    path = path,
    uri = change.uri,
    dir = vim.fs.dirname(path),
    ext = path_ext(path),
    change = change,
    index = index,
  }
end

local function push_rename(events, deleted, created)
  events[#events + 1] = {
    type = "renamed",
    old_path = deleted.path,
    old_uri = deleted.uri,
    new_path = created.path,
    new_uri = created.uri,
    index = math.min(deleted.index, created.index),
  }
end

local function push_raw(events, event)
  events[#events + 1] = {
    type = event.type,
    path = event.path,
    uri = event.uri,
    index = event.index,
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

local function pair_dir_renames(created_events, deleted_events, used_created, used_deleted, normalized)
  local grouped_created = {}
  local grouped_deleted = {}

  for i, event in ipairs(created_events) do
    if not used_created[i] then
      local key = event.dir .. "\0" .. event.ext
      grouped_created[key] = grouped_created[key] or {}
      grouped_created[key][#grouped_created[key] + 1] = i
    end
  end

  for i, event in ipairs(deleted_events) do
    if not used_deleted[i] then
      local key = event.dir .. "\0" .. event.ext
      grouped_deleted[key] = grouped_deleted[key] or {}
      grouped_deleted[key][#grouped_deleted[key] + 1] = i
    end
  end

  for key, delete_indexes in pairs(grouped_deleted) do
    local create_indexes = grouped_created[key]
    if create_indexes then
      for _, deleted_index in ipairs(delete_indexes) do
        local deleted = deleted_events[deleted_index]
        local best_created_index
        local best_distance

        for _, created_index in ipairs(create_indexes) do
          if not used_created[created_index] then
            local created = created_events[created_index]
            local distance = math.abs(created.index - deleted.index)
            if best_distance == nil or distance < best_distance then
              best_created_index = created_index
              best_distance = distance
            end
          end
        end

        if best_created_index then
          used_deleted[deleted_index] = true
          used_created[best_created_index] = true
          push_rename(normalized, deleted, created_events[best_created_index])
        end
      end
    end
  end
end

local function pair_cross_dir_rename(created_events, deleted_events, used_created, used_deleted, normalized)
  local remaining_created = {}
  local remaining_deleted = {}

  for i, event in ipairs(created_events) do
    if not used_created[i] then
      remaining_created[#remaining_created + 1] = { index = i, event = event }
    end
  end

  for i, event in ipairs(deleted_events) do
    if not used_deleted[i] then
      remaining_deleted[#remaining_deleted + 1] = { index = i, event = event }
    end
  end

  if #remaining_created == 1 and #remaining_deleted == 1 then
    local created = remaining_created[1]
    local deleted = remaining_deleted[1]
    if created.event.ext == deleted.event.ext then
      used_created[created.index] = true
      used_deleted[deleted.index] = true
      push_rename(normalized, deleted.event, created.event)
    end
  end
end

---@param changes lsp.FileEvent[]
---@return table[]
M.normalize = function(changes)
  local created_events = {}
  local deleted_events = {}
  local normalized = {}

  for index, change in ipairs(changes) do
    local event = build_event(change, index)
    if event then
      if event.type == "created" then
        created_events[#created_events + 1] = event
      elseif event.type == "deleted" then
        deleted_events[#deleted_events + 1] = event
      else
        push_raw(normalized, event)
      end
    end
  end

  local used_created = {}
  local used_deleted = {}

  pair_dir_renames(created_events, deleted_events, used_created, used_deleted, normalized)
  pair_cross_dir_rename(created_events, deleted_events, used_created, used_deleted, normalized)

  for i, event in ipairs(created_events) do
    if not used_created[i] then
      push_raw(normalized, event)
    end
  end

  for i, event in ipairs(deleted_events) do
    if not used_deleted[i] then
      push_raw(normalized, event)
    end
  end

  return sort_by_index(normalized)
end

---@param handler fun(events: table[], raw_changes: lsp.FileEvent[])
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

  if #handlers == 0 then
    vim.print(events)
    return events
  end

  for _, handler in ipairs(handlers) do
    util.fire_callback("watchfiles", handler, events, changes)
  end

  return events
end

return M
