local M = {}

local namespaces = {
  file = true,
  formula = true,
  note = true,
}

local context_identifiers = {
  file = true,
  formula = true,
  note = true,
  this = true,
  values = true,
}

---@param namespace "note"|"file"|"formula"
---@param name string
---@param source string
---@param explicit boolean
---@return obsidian.base.PropertyReference
local function reference(namespace, name, source, explicit)
  return {
    namespace = namespace,
    name = name,
    source = source,
    explicit = explicit,
    canonical = namespace .. "." .. name,
  }
end

---Resolve a bare expression identifier. Bases treats it as a note property
---unless it names one of the expression context objects.
---@param name string
---@return obsidian.base.PropertyReference?
function M.from_identifier(name)
  if context_identifiers[name] then
    return nil
  end
  return reference("note", name, name, false)
end

---Resolve direct member access on a property namespace.
---@param object obsidian.base.Expression
---@param name string
---@return obsidian.base.PropertyReference?
function M.from_member(object, name)
  if object.kind ~= "identifier" or not namespaces[object.name] then
    return nil
  end
  local namespace = object.name
  ---@cast namespace "note"|"file"|"formula"
  return reference(namespace, name, namespace .. "." .. name, true)
end

---Resolve indexed access such as `note["release date"]`.
---@param object obsidian.base.Expression
---@param index obsidian.base.Expression
---@return obsidian.base.PropertyReference?
function M.from_index(object, index)
  if
    object.kind ~= "identifier"
    or not namespaces[object.name]
    or index.kind ~= "literal"
    or type(index.value) ~= "string"
  then
    return nil
  end
  local namespace = object.name
  ---@cast namespace "note"|"file"|"formula"
  return reference(namespace, index.value, namespace .. "[" .. index.raw .. "]", true)
end

---Normalize a property name used by view configuration. An unqualified name
---is shorthand for a note property.
---@param source string
---@return obsidian.base.PropertyReference
function M.parse(source)
  source = vim.trim(source)
  local namespace, name = source:match "^(note)%.(.+)$"
  if namespace == nil then
    namespace, name = source:match "^(file)%.(.+)$"
  end
  if namespace == nil then
    namespace, name = source:match "^(formula)%.(.+)$"
  end
  if namespace ~= nil and name ~= "" then
    ---@cast namespace "note"|"file"|"formula"
    ---@cast name string
    return reference(namespace, name, source, true)
  end
  return reference("note", source, source, false)
end

return M
