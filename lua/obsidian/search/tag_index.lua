local api = require "obsidian.api"
local fs_util = require "obsidian.util.fs"
local tag = require "obsidian.tag"
local volatile = require "obsidian.cache.volatile"

local M = {}

local function event_deleted(event)
  return event.type == "deleted" or event.type == vim.lsp.protocol.FileChangeType.Deleted
end

local function normalize(path)
  path = vim.fn.resolve(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function in_scope(path, context)
  if not fs_util.is_subpath(path, context.dir) or not api.path_is_note(path, context.workspace) then
    return false
  end
  local relative = fs_util.relpath(context.workspace_root, path)
  return relative ~= nil and (not context.ignore_checker or not context.ignore_checker:check(relative))
end

local index = volatile.vault_index {
  version = function(context)
    return context.version
  end,
  matches = function(_, events, context)
    for _, event in ipairs(events) do
      for _, path in ipairs { event.path, event.old_path, event.new_path } do
        if path and fs_util.is_subpath(normalize(path), context.dir) then
          return true
        end
      end
    end
    return false
  end,
  build = function(context, done)
    context.scan(function(locations, err)
      if err then
        done(nil, err)
        return
      end
      local by_path = {}
      for _, location in ipairs(locations) do
        local path = normalize(tostring(location.path))
        by_path[path] = by_path[path] or {}
        by_path[path][#by_path[path] + 1] = location
      end
      done { by_path = by_path, overlays = {} }
    end)
  end,
  update = function(value, events, context)
    for _, event in ipairs(events) do
      if event.type == "renamed" and event.old_path and event.new_path then
        local old_path = normalize(event.old_path)
        local new_path = normalize(event.new_path)
        value.by_path[old_path] = nil
        value.overlays[old_path] = nil
        if in_scope(new_path, context) then
          value.by_path[new_path] = context.parse_path(new_path)
        end
      elseif event.path then
        local path = normalize(event.path)
        if fs_util.is_subpath(path, context.dir) then
          value.overlays[path] = nil
          if event_deleted(event) or not in_scope(path, context) then
            value.by_path[path] = nil
          else
            value.by_path[path] = context.parse_path(path)
          end
        end
      end
    end
    return true
  end,
}

local function active_overlays(value, context)
  local active = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      local path = name ~= "" and normalize(name) or nil
      if path and in_scope(path, context) then
        local base = value.by_path[path]
        local cached = value.overlays[path]
        if not base or vim.bo[bufnr].modified or cached then
          local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
          if not cached or cached.bufnr ~= bufnr or cached.changedtick ~= changedtick then
            cached = {
              bufnr = bufnr,
              changedtick = changedtick,
              locations = context.parse_buffer(bufnr),
            }
          end
          active[path] = cached
        end
      end
    end
  end
  value.overlays = active
  return active
end

local function normalize_terms(term)
  local input = type(term) == "string" and { term } or term
  local terms, seen = {}, {}
  for _, value in ipairs(input) do
    value = tag.normalize(value)
    if not seen[value] then
      terms[#terms + 1] = value
      seen[value] = true
    end
  end
  return terms
end

---@param term string|string[]
---@param callback fun(locations: obsidian.search.TagLocation[])
---@param context table
function M.find(term, callback, context)
  index:get(context.dir, context, function(value)
    if not value then
      callback {}
      return
    end

    local terms = normalize_terms(term)
    local overlays = active_overlays(value, context)
    local paths = {}
    for path in pairs(value.by_path) do
      if not overlays[path] then
        paths[#paths + 1] = path
      end
    end
    for path in pairs(overlays) do
      paths[#paths + 1] = path
    end
    table.sort(paths)

    local results = {}
    for _, path in ipairs(paths) do
      local locations = overlays[path] and overlays[path].locations or value.by_path[path]
      for _, location in ipairs(locations or {}) do
        for _, query in ipairs(terms) do
          if tag.matches(location.tag, query, context.match or "prefix") then
            results[#results + 1] = location
            break
          end
        end
      end
    end
    callback(results)
  end)
end

return M
