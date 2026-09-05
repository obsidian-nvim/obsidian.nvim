local cache = require "obsidian.cache"
local log = require "obsidian.log"
local Path = require "obsidian.path"
local picker = require "obsidian.picker"
local picker_util = require "obsidian.picker.util"
local util = require "obsidian.util"
local yaml = require "obsidian.yaml"

local M = {}

---@class obsidian.commands.properties.ValueEntry
---@field key string
---@field value string
---@field count integer
---@field paths string[]

---@class obsidian.commands.properties.KeyEntry
---@field key string
---@field count integer
---@field values table<string, obsidian.commands.properties.ValueEntry>

---Flatten a property value into a list of display/lookup strings.
---
---List values contribute each of their scalar items. Mapping values contribute
---their keys and scalar items, matching the frontmatter tag flattening in the
---cache index.
---
---@param value any
---@param out string[]
local function flatten_value(value, out)
  if value == vim.NIL or value == nil then
    return
  elseif type(value) == "table" then
    for key, item in pairs(value) do
      if not vim.islist(value) then
        out[#out + 1] = tostring(key)
      end
      flatten_value(item, out)
    end
  else
    out[#out + 1] = tostring(value)
  end
end

---Normalize a command line or smart action value argument so it matches the
---cached scalar representation (e.g. quoted strings, numbers, booleans).
---
---@param value any
---@return string?
local function normalize_arg(value)
  if type(value) ~= "string" then
    return value
  end

  local ok, parsed = pcall(yaml.loads, value)
  if ok and parsed ~= nil and type(parsed) ~= "table" then
    return tostring(parsed)
  end

  return value
end

---Build an index of vault properties from the cache.
---
---@param rows table<string, table>
---@return table<string, obsidian.commands.properties.KeyEntry>
local function build_index(rows)
  local index = {}

  for path, row in pairs(rows) do
    local properties = (row.frontmatter and row.frontmatter.values) or row.properties or {}
    for key, value in pairs(properties) do
      -- Frontmatter must be a mapping. Skip numeric keys produced by YAML
      -- sequences so top-level list items don't show up as property keys.
      if type(key) == "string" then
        local key_entry = index[key]
        if not key_entry then
          key_entry = { key = key, count = 0, values = {} }
          index[key] = key_entry
        end
        key_entry.count = key_entry.count + 1

        local flat = {}
        flatten_value(value, flat)

        -- A property without a scalar value still counts as a key, but does not
        -- get a value entry.
        local seen = {}
        for _, str in ipairs(flat) do
          if not seen[str] then
            seen[str] = true
            local value_entry = key_entry.values[str]
            if not value_entry then
              value_entry = { key = key, value = str, count = 0, paths = {} }
              key_entry.values[str] = value_entry
            end
            value_entry.count = value_entry.count + 1
            value_entry.paths[#value_entry.paths + 1] = path
          end
        end
      end
    end
  end

  return index
end

---@param key_entries obsidian.commands.properties.KeyEntry[]
local function sort_key_entries(key_entries)
  table.sort(key_entries, function(a, b)
    if a.count == b.count then
      return tostring(a.key) < tostring(b.key)
    end
    return a.count > b.count
  end)
end

---@param value_entries obsidian.commands.properties.ValueEntry[]
local function sort_value_entries(value_entries)
  table.sort(value_entries, function(a, b)
    if a.count == b.count then
      return a.value < b.value
    end
    return a.count > b.count
  end)
end

---@param value_entry obsidian.commands.properties.ValueEntry
local function list_notes(value_entry)
  local paths = vim.deepcopy(value_entry.paths)
  table.sort(paths)

  local entries = vim.tbl_map(function(path)
    return {
      filename = path,
      text = tostring(Path.new(path):vault_relative_path()),
    }
  end, paths)

  picker.select(entries, {
    prompt = ("Property '%s: %s'"):format(value_entry.key, value_entry.value),
    format_item = function(item)
      return item.text
    end,
    preview_item = function(item)
      return util.preview_path(item.filename)
    end,
  }, function(items)
    if vim.tbl_isempty(items) then
      return
    end
    picker_util.open_notes(items)
  end)
end

---@param key_entry obsidian.commands.properties.KeyEntry
local function list_values(key_entry)
  local value_entries = vim.tbl_values(key_entry.values)
  sort_value_entries(value_entries)

  picker.select(value_entries, {
    prompt = ("Property '%s'"):format(key_entry.key),
    format_item = function(item)
      return item.value .. "  " .. item.count
    end,
  }, function(items)
    if vim.tbl_isempty(items) then
      return
    end
    list_notes(items[1])
  end)
end

---@param index table<string, obsidian.commands.properties.KeyEntry>
local function list_keys(index)
  local key_entries = vim.tbl_values(index)
  sort_key_entries(key_entries)

  picker.select(key_entries, {
    prompt = "Properties",
    format_item = function(item)
      return item.key .. "  " .. item.count
    end,
  }, function(items)
    if vim.tbl_isempty(items) then
      return
    end
    list_values(items[1])
  end)
end

---Start the properties picker.
---
---With no arguments the picker starts at the list of vault property keys.
---With a key it starts at the list of values for that key. With a key and a
---value it starts at the list of notes containing that key/value pair.
---
---@param key string|?
---@param value any|?
function M.pick(key, value)
  if not cache.is_enabled() then
    return log.warn "Properties search requires the cache to be enabled (opts.cache.enabled = true)"
  end

  cache.when_ready(function()
    local index = build_index(cache.notes.all())

    if key == nil or key == "" then
      return list_keys(index)
    end

    local key_entry = index[key]
    if not key_entry then
      return log.warn("No notes have property '%s'", key)
    end

    if value == nil then
      return list_values(key_entry)
    end

    value = normalize_arg(value)
    local value_entry = key_entry.values[value]
    if not value_entry then
      return log.warn("No notes have property '%s: %s'", key, value)
    end

    list_notes(value_entry)
  end)
end

return setmetatable(M, {
  __call = function(_, data)
    local fargs = data.fargs or {}
    if #fargs > 2 then
      return log.warn "Obsidian properties expects at most a key and a value"
    end
    return M.pick(fargs[1], fargs[2])
  end,
})
