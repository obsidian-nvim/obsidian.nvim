local api = require "obsidian.api"
local search = require "obsidian.search"

local M = {}

---@class obsidian.PropertyRecord
---@field path string
---@field display_name string
---@field properties table<string, any>

---@class obsidian.PropertyCount
---@field name string
---@field count integer

---@param counts table<string, integer>
---@return obsidian.PropertyCount[]
local function sorted_counts(counts)
  local entries = {}
  for name, count in pairs(counts) do
    entries[#entries + 1] = { name = name, count = count }
  end
  table.sort(entries, function(a, b)
    return a.name < b.name
  end)
  return entries
end

---@param notes obsidian.Note[]
---@return obsidian.PropertyRecord[]
M.from_notes = function(notes)
  local records = {}
  for _, note in ipairs(notes) do
    local properties = vim.deepcopy(note.metadata or {})
    if #note.aliases == 0 then
      properties.aliases = nil
    end
    if #note.tags == 0 then
      properties.tags = nil
    end
    records[#records + 1] = {
      path = tostring(note.path),
      display_name = note:display_name(),
      properties = properties,
    }
  end
  return records
end

---@param rows table<string, table>
---@return obsidian.PropertyRecord[]
M.from_cache = function(rows)
  local cache = require "obsidian.cache"
  local records = {}
  for path, row in pairs(rows) do
    local display_name = (row.id and tostring(row.id))
      or (row.aliases and row.aliases[#row.aliases])
      or cache.notes.basename(path)
    records[#records + 1] = {
      path = path,
      display_name = display_name,
      properties = row.properties or {},
    }
  end
  return records
end

---@param records obsidian.PropertyRecord[]
---@return obsidian.PropertyCount[]
M.keys = function(records)
  local counts = {}
  for _, record in ipairs(records) do
    for key in pairs(record.properties) do
      counts[key] = (counts[key] or 0) + 1
    end
  end
  return sorted_counts(counts)
end

---@param records obsidian.PropertyRecord[]
---@param key string
---@return obsidian.PropertyCount[]
M.values = function(records, key)
  local counts = {}
  for _, record in ipairs(records) do
    local value = record.properties[key]
    if value ~= nil and value ~= vim.NIL then
      local seen = {}
      if vim.islist(value) then
        for _, item in ipairs(value) do
          if item ~= vim.NIL then
            seen[tostring(item)] = true
          end
        end
      else
        seen[tostring(value)] = true
      end
      for item in pairs(seen) do
        counts[item] = (counts[item] or 0) + 1
      end
    end
  end
  return sorted_counts(counts)
end

---@param record obsidian.PropertyRecord
---@param key string
---@param value string
---@return boolean
M.has_value = function(record, key, value)
  local prop = record.properties[key]
  if prop == nil or prop == vim.NIL then
    return false
  end
  if vim.islist(prop) then
    for _, item in ipairs(prop) do
      if item ~= vim.NIL and tostring(item) == value then
        return true
      end
    end
    return false
  end
  return tostring(prop) == value
end

---@param opts { dir: string? }|?
---@param callback fun(keys: obsidian.PropertyCount[], records: obsidian.PropertyRecord[])
M.list_async = function(opts, callback)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if cache.is_enabled() then
    cache.when_ready(function()
      local records = M.from_cache(cache.notes.all())
      callback(M.keys(records), records)
    end)
    return
  end

  local dir = opts.dir or api.resolve_workspace_dir()
  search.find_notes_async("", function(notes)
    local records = M.from_notes(notes)
    callback(M.keys(records), records)
  end, { dir = dir })
end

return M
