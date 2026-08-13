local M = {}

local DEFAULT_FIELDS = { "id", "aliases" }

---@return string[]
local function configured_fields()
  local fields = Obsidian and Obsidian.opts and Obsidian.opts.note and Obsidian.opts.note.identifiers
  if type(fields) ~= "table" or not vim.islist(fields) then
    return DEFAULT_FIELDS
  end
  return fields
end

---@param value any
---@param identifiers string[]
local function add_value(value, identifiers)
  if type(value) == "table" and vim.islist(value) then
    for _, item in ipairs(value) do
      add_value(item, identifiers)
    end
  elseif type(value) == "string" or type(value) == "number" then
    value = tostring(value)
    if value ~= "" then
      identifiers[#identifiers + 1] = value
    end
  end
end

---@param values string[]
---@return string[]
function M.unique(values)
  local identifiers = {}
  local seen = {}
  for _, value in ipairs(values) do
    if not seen[value] then
      identifiers[#identifiers + 1] = value
      seen[value] = true
    end
  end
  return identifiers
end

---@param get_value fun(field: string): any
---@return string[]
local function collect(get_value)
  local identifiers = {}
  for _, field in ipairs(configured_fields()) do
    add_value(get_value(field), identifiers)
  end
  return M.unique(identifiers)
end

---Return the configured identifiers from a loaded note.
---@param note obsidian.Note
---@return string[]
function M.from_note(note)
  return collect(function(field)
    if field == "id" then
      return note.id
    elseif field == "aliases" then
      return note.aliases
    elseif field == "title" then
      return note.title or (note.metadata and note.metadata.title)
    end
    return note.metadata and note.metadata[field]
  end)
end

---Return the configured identifiers from a compact cache row.
---@param path string
---@param row table
---@return string[]
function M.from_cache(path, row)
  return collect(function(field)
    if field == "id" then
      return row.id or vim.fn.fnamemodify(path, ":t:r")
    elseif field == "aliases" then
      return row.aliases
    elseif field == "title" and row.title ~= nil then
      return row.title
    end
    return row.properties and row.properties[field]
  end)
end

return M
