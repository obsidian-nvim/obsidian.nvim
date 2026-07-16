local expression = require "obsidian.base.expression"
local yaml = require "obsidian.yaml"

local M = {}

local top_level_keys = {
  filters = true,
  formulas = true,
  properties = true,
  summaries = true,
  views = true,
}

local view_keys = {
  type = true,
  name = true,
  filters = true,
  order = true,
  sort = true,
  groupBy = true,
  summaries = true,
  limit = true,
}

---@param diagnostics obsidian.base.Diagnostic[]
---@param code string
---@param message string
---@param path? string
---@param severity? obsidian.base.DiagnosticSeverity
local function diagnostic(diagnostics, code, message, path, severity)
  diagnostics[#diagnostics + 1] = {
    code = code,
    message = message,
    path = path,
    severity = severity or "error",
  }
end

---@param value any
---@return boolean
local function is_mapping(value)
  return type(value) == "table" and (next(value) == nil or not vim.islist(value))
end

---@param value table
---@param known table<string, boolean>
---@return table<string, any>
local function extra_keys(value, known)
  local extra = {}
  for key, item in pairs(value) do
    if not known[key] then
      extra[key] = vim.deepcopy(item)
    end
  end
  return extra
end

---@param source string
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return obsidian.base.Expression?
local function parse_expression(source, path, diagnostics)
  local ast, expression_diagnostics = expression.parse(source)
  for _, item in ipairs(expression_diagnostics) do
    item.path = path
    diagnostics[#diagnostics + 1] = item
  end
  return ast
end

---@param value any
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return obsidian.base.Filter?
local function parse_filter(value, path, diagnostics)
  if value == nil or value == vim.NIL then
    return nil
  elseif type(value) == "string" then
    return {
      kind = "filter_expression",
      source = value,
      expression = parse_expression(value, path, diagnostics),
    }
  elseif not is_mapping(value) then
    diagnostic(diagnostics, "base.invalid-filter", "filter must be an expression or a filter group", path)
    return nil
  end

  local operators = {}
  for _, operator in ipairs { "and", "or", "not" } do
    if value[operator] ~= nil then
      operators[#operators + 1] = operator
    end
  end
  if #operators ~= 1 then
    diagnostic(
      diagnostics,
      "base.invalid-filter-group",
      "filter group must contain exactly one of 'and', 'or', or 'not'",
      path
    )
    return nil
  end

  ---@type "and"|"or"|"not"
  local operator = operators[1]
  local raw_children = value[operator]
  if not vim.islist(raw_children) then
    raw_children = { raw_children }
  end
  local children = {}
  for index, child in ipairs(raw_children) do
    local parsed = parse_filter(child, ("%s.%s[%d]"):format(path, operator, index), diagnostics)
    if parsed ~= nil then
      children[#children + 1] = parsed
    end
  end
  if #children == 0 then
    diagnostic(diagnostics, "base.empty-filter-group", "filter group must contain at least one filter", path)
  end

  return {
    kind = "filter_group",
    operator = operator,
    children = children,
  }
end

---@param values any
---@param kind "formula"|"summary"
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return table<string, obsidian.base.ExpressionDeclaration>
local function parse_declarations(values, kind, path, diagnostics)
  local declarations = {}
  if values == nil or values == vim.NIL then
    return declarations
  elseif not is_mapping(values) then
    diagnostic(diagnostics, "base.invalid-" .. path, path .. " must be a mapping", path)
    return declarations
  end

  for name, source in pairs(values) do
    local declaration_path = path .. "." .. tostring(name)
    if type(source) ~= "string" then
      diagnostic(diagnostics, "base.invalid-" .. kind, kind .. " expression must be a string", declaration_path)
    else
      local ast
      if vim.trim(source) ~= "" then
        ast = parse_expression(source, declaration_path, diagnostics)
      end
      declarations[name] = {
        kind = kind,
        name = name,
        source = source,
        expression = ast,
      }
    end
  end
  return declarations
end

---@param value any
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return string[]
local function parse_order(value, path, diagnostics)
  if value == nil or value == vim.NIL then
    return {}
  elseif not vim.islist(value) then
    diagnostic(diagnostics, "base.invalid-order", "view order must be a list of property names", path)
    return {}
  end
  local order = {}
  for index, property in ipairs(value) do
    if type(property) ~= "string" then
      diagnostic(
        diagnostics,
        "base.invalid-property-reference",
        "ordered property must be a string",
        ("%s[%d]"):format(path, index)
      )
    else
      order[#order + 1] = property
    end
  end
  return order
end

---@param value any
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return table[]
local function parse_sort(value, path, diagnostics)
  if value == nil or value == vim.NIL then
    return {}
  elseif not vim.islist(value) then
    diagnostic(diagnostics, "base.invalid-sort", "view sort must be a list", path)
    return {}
  end
  local sort = {}
  for index, spec in ipairs(value) do
    if not is_mapping(spec) or type(spec.property) ~= "string" then
      diagnostic(
        diagnostics,
        "base.invalid-sort-entry",
        "sort entry must contain a string 'property' field",
        ("%s[%d]"):format(path, index)
      )
    else
      sort[#sort + 1] = vim.deepcopy(spec)
    end
  end
  return sort
end

---@param value any
---@param path string
---@param diagnostics obsidian.base.Diagnostic[]
---@return table<string, string>
local function parse_view_summaries(value, path, diagnostics)
  if value == nil or value == vim.NIL then
    return {}
  elseif not is_mapping(value) then
    diagnostic(diagnostics, "base.invalid-view-summaries", "view summaries must be a mapping", path)
    return {}
  end
  local summaries = {}
  for property, summary in pairs(value) do
    if type(summary) ~= "string" then
      diagnostic(
        diagnostics,
        "base.invalid-view-summary",
        "view summary name must be a string",
        path .. "." .. tostring(property)
      )
    else
      summaries[property] = summary
    end
  end
  return summaries
end

---@param value any
---@param index integer
---@param diagnostics obsidian.base.Diagnostic[]
---@return obsidian.base.View?
local function parse_view(value, index, diagnostics)
  local path = ("views[%d]"):format(index)
  if not is_mapping(value) then
    diagnostic(diagnostics, "base.invalid-view", "view must be a mapping", path)
    return nil
  end
  if type(value.type) ~= "string" or value.type == "" then
    diagnostic(diagnostics, "base.missing-view-type", "view must have a non-empty string 'type'", path)
  end
  if type(value.name) ~= "string" or value.name == "" then
    diagnostic(diagnostics, "base.missing-view-name", "view should have a non-empty string 'name'", path, "warning")
  end
  if value.limit ~= nil and value.limit ~= vim.NIL and type(value.limit) ~= "number" then
    diagnostic(diagnostics, "base.invalid-view-limit", "view limit must be a number", path .. ".limit")
  end
  if value.groupBy ~= nil and value.groupBy ~= vim.NIL and not is_mapping(value.groupBy) then
    diagnostic(diagnostics, "base.invalid-group-by", "view groupBy must be a mapping", path .. ".groupBy")
  end

  return {
    kind = "view",
    type = type(value.type) == "string" and value.type or nil,
    name = type(value.name) == "string" and value.name or nil,
    filters = parse_filter(value.filters, path .. ".filters", diagnostics),
    order = parse_order(value.order, path .. ".order", diagnostics),
    sort = parse_sort(value.sort, path .. ".sort", diagnostics),
    group_by = is_mapping(value.groupBy) and vim.deepcopy(value.groupBy) or nil,
    summaries = parse_view_summaries(value.summaries, path .. ".summaries", diagnostics),
    limit = type(value.limit) == "number" and value.limit or nil,
    config = extra_keys(value, view_keys),
    raw = value,
  }
end

---Parse and validate a `.base` document without executing its queries.
---@param source string
---@return obsidian.base.Document?
---@return obsidian.base.Diagnostic[]
function M.parse(source)
  ---@type obsidian.base.Diagnostic[]
  local diagnostics = {}
  local ok, data_or_error = pcall(yaml.loads, source)
  if not ok then
    local message = tostring(data_or_error)
    local line = tonumber(message:match "%[line=(%d+)%]")
    diagnostics[1] = {
      code = "base.invalid-yaml",
      message = message,
      severity = "error",
      line = line and math.max(math.floor(line) - 1, 0) or nil,
    }
    return nil, diagnostics
  end

  local data = data_or_error
  if not is_mapping(data) then
    diagnostic(diagnostics, "base.invalid-document", "base document must contain a YAML mapping")
    return nil, diagnostics
  end
  ---@cast data table

  local views = {}
  if data.views == nil or data.views == vim.NIL then
    diagnostic(diagnostics, "base.missing-views", "base document must define at least one view", "views")
  elseif not vim.islist(data.views) then
    diagnostic(diagnostics, "base.invalid-views", "views must be a list", "views")
  else
    for index, value in ipairs(data.views) do
      local view = parse_view(value, index, diagnostics)
      if view ~= nil then
        views[#views + 1] = view
      end
    end
    if #data.views == 0 then
      diagnostic(diagnostics, "base.missing-views", "base document must define at least one view", "views")
    end
  end

  local properties = {}
  if data.properties ~= nil and data.properties ~= vim.NIL then
    if is_mapping(data.properties) then
      properties = vim.deepcopy(data.properties)
    else
      diagnostic(diagnostics, "base.invalid-properties", "properties must be a mapping", "properties")
    end
  end

  ---@type obsidian.base.Document
  local document = {
    kind = "base",
    source = source,
    filters = parse_filter(data.filters, "filters", diagnostics),
    formulas = parse_declarations(data.formulas, "formula", "formulas", diagnostics),
    properties = properties,
    summaries = parse_declarations(data.summaries, "summary", "summaries", diagnostics),
    views = views,
    config = extra_keys(data, top_level_keys),
    raw = data,
  }
  return document, diagnostics
end

M.parse_filter = parse_filter

return M
