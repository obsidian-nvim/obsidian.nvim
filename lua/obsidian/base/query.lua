local cache = require "obsidian.cache"
local cache_note = require "obsidian.cache.note"
local ignore = require "obsidian.ignore"
local property = require "obsidian.base.property"

local M = {}

local NOTE_EXTENSIONS = { md = true, markdown = true, qmd = true }
local fallback_snapshot

---@param path string
---@return string
local function relative_path(path)
  local root = vim.fs.normalize(tostring(Obsidian.dir)):gsub("/+$", "")
  path = vim.fs.normalize(path)
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

---@param path string
---@param row table
---@return table
local function candidate(path, row)
  local rel = relative_path(path)
  local stat = vim.uv.fs_stat(path)
  local filename = vim.fs.basename(path)
  local stem = filename:gsub("%.[^.]+$", "")
  local ext = filename:match "%.([^.]+)$" or ""
  local folder = vim.fs.dirname(rel)
  if folder == "." then
    folder = ""
  end
  return {
    path = path,
    row = row,
    note = row.properties or {},
    file = {
      name = stem,
      path = rel,
      folder = folder,
      ext = ext,
      size = row.size or (stat and stat.size),
      ctime = stat and stat.ctime.sec or nil,
      mtime = row.mtime or (stat and stat.mtime.sec),
      tags = row.tags or {},
      aliases = row.aliases or {},
    },
    formulas = {},
    formula_stack = {},
  }
end

---@return table[]
local function collect_candidates()
  local result = {}
  if cache.is_enabled() and cache.is_ready() then
    for path, row in pairs(cache.notes.all()) do
      local ext = (path:match "%.([^./]+)$" or ""):lower()
      if NOTE_EXTENSIONS[ext] then
        result[#result + 1] = candidate(path, row)
      end
    end
  else
    local root = vim.fs.normalize(tostring(Obsidian.dir))
    if fallback_snapshot == nil or fallback_snapshot.root ~= root then
      local rows = {}
      local paths = vim.fs.find(function(name, dir)
        local ext = (name:match "%.([^./]+)$" or ""):lower()
        return NOTE_EXTENSIONS[ext] == true and not ignore.is_ignored(vim.fs.joinpath(dir, name))
      end, { path = root, type = "file", limit = math.huge })
      for _, path in ipairs(paths) do
        local normalized = vim.fs.normalize(path)
        local row = cache_note.build(normalized, root)
        if row ~= nil then
          rows[#rows + 1] = { path = normalized, row = row }
        end
      end
      fallback_snapshot = { root = root, rows = rows }
    end
    for _, item in ipairs(fallback_snapshot.rows) do
      result[#result + 1] = candidate(item.path, item.row)
    end
  end
  table.sort(result, function(a, b)
    return a.path < b.path
  end)
  return result
end

---@param value any
---@return boolean
local function truthy(value)
  return value ~= nil and value ~= vim.NIL and value ~= false
end

---@param ctx table
---@param ref obsidian.base.PropertyReference
---@param document obsidian.base.Document
---@return any
---@return string?
local function get_property(ctx, ref, document)
  if ref.namespace == "note" then
    if ref.name == "tags" then
      return ctx.file.tags
    elseif ref.name == "aliases" then
      return ctx.file.aliases
    end
    return ctx.note[ref.name]
  elseif ref.namespace == "file" then
    return ctx.file[ref.name]
  end

  local cached = ctx.formulas[ref.name]
  if cached ~= nil then
    return cached == vim.NIL and nil or cached
  end
  if ctx.formula_stack[ref.name] then
    return nil, "cyclic formula: " .. ref.name
  end
  local declaration = document.formulas[ref.name]
  if declaration == nil or declaration.expression == nil then
    return nil
  end
  ctx.formula_stack[ref.name] = true
  local value, err = M.evaluate(declaration.expression, ctx, document)
  ctx.formula_stack[ref.name] = nil
  if err == nil then
    ctx.formulas[ref.name] = value == nil and vim.NIL or value
  end
  return value, err
end

---@param callee obsidian.base.Expression
---@return string?
---@return obsidian.base.Expression?
local function call_name(callee)
  if callee.kind == "identifier" then
    return callee.name, nil
  elseif callee.kind == "member" then
    return callee.property, callee.object
  end
  return nil, nil
end

---@param expression obsidian.base.Expression
---@param ctx table
---@param document obsidian.base.Document
---@return any
---@return string?
function M.evaluate(expression, ctx, document)
  if expression.kind == "literal" then
    return expression.value == vim.NIL and nil or expression.value
  elseif expression.reference ~= nil then
    return get_property(ctx, expression.reference, document)
  elseif expression.kind == "identifier" then
    if expression.name == "file" then
      return ctx.file
    elseif expression.name == "note" then
      return ctx.note
    elseif expression.name == "formula" then
      return ctx.formulas
    end
    return nil, "unknown identifier: " .. expression.name
  elseif expression.kind == "group" then
    return M.evaluate(expression.expression, ctx, document)
  elseif expression.kind == "member" then
    local object, err = M.evaluate(expression.object, ctx, document)
    if err ~= nil then
      return nil, err
    end
    return type(object) == "table" and object[expression.property] or nil
  elseif expression.kind == "index" then
    local object, object_err = M.evaluate(expression.object, ctx, document)
    if object_err ~= nil then
      return nil, object_err
    end
    local index, index_err = M.evaluate(expression.index, ctx, document)
    if index_err ~= nil then
      return nil, index_err
    end
    return type(object) == "table" and object[index] or nil
  elseif expression.kind == "unary" then
    local operand, err = M.evaluate(expression.operand, ctx, document)
    if err ~= nil then
      return nil, err
    elseif expression.operator == "!" then
      return not truthy(operand)
    elseif expression.operator == "-" then
      return -operand
    elseif expression.operator == "+" then
      return operand
    end
  elseif expression.kind == "binary" then
    local left, left_err = M.evaluate(expression.left, ctx, document)
    if left_err ~= nil then
      return nil, left_err
    end
    if expression.operator == "&&" and not truthy(left) then
      return false
    elseif expression.operator == "||" and truthy(left) then
      return left
    end
    local right, right_err = M.evaluate(expression.right, ctx, document)
    if right_err ~= nil then
      return nil, right_err
    end
    local op = expression.operator
    if op == "&&" then
      return truthy(right)
    elseif op == "||" then
      return right
    elseif op == "==" then
      return vim.deep_equal(left, right)
    elseif op == "!=" then
      return not vim.deep_equal(left, right)
    end
    local ok, value = pcall(function()
      if op == ">" then
        return left > right
      elseif op == "<" then
        return left < right
      elseif op == ">=" then
        return left >= right
      elseif op == "<=" then
        return left <= right
      elseif op == "+" then
        return left + right
      elseif op == "-" then
        return left - right
      elseif op == "*" then
        return left * right
      elseif op == "/" then
        return left / right
      elseif op == "%" then
        return left % right
      end
    end)
    if not ok then
      return nil, tostring(value)
    end
    return value
  elseif expression.kind == "call" then
    local name, receiver_expression = call_name(expression.callee)
    local arguments = {}
    for _, argument in ipairs(expression.arguments) do
      local value, err = M.evaluate(argument, ctx, document)
      if err ~= nil then
        return nil, err
      end
      arguments[#arguments + 1] = value
    end

    if
      receiver_expression ~= nil
      and receiver_expression.kind == "identifier"
      and receiver_expression.name == "file"
    then
      if name == "hasTag" then
        local wanted = tostring(arguments[1] or ""):gsub("^#", ""):lower()
        for _, tag in ipairs(ctx.file.tags) do
          if tostring(tag):gsub("^#", ""):lower() == wanted then
            return true
          end
        end
        return false
      elseif name == "hasProperty" then
        return ctx.note[tostring(arguments[1])] ~= nil
      elseif name == "inFolder" then
        local folder = tostring(arguments[1] or ""):gsub("/+$", "")
        return ctx.file.folder == folder or vim.startswith(ctx.file.folder, folder .. "/")
      end
    elseif name == "now" and receiver_expression == nil then
      return os.time()
    end

    local receiver, receiver_err
    if receiver_expression ~= nil then
      receiver, receiver_err = M.evaluate(receiver_expression, ctx, document)
      if receiver_err ~= nil then
        return nil, receiver_err
      end
    end
    if name == "contains" then
      if type(receiver) == "string" then
        return receiver:find(tostring(arguments[1]), 1, true) ~= nil
      elseif type(receiver) == "table" then
        return vim.list_contains(receiver, arguments[1])
      end
    elseif name == "startsWith" and type(receiver) == "string" then
      return vim.startswith(receiver, tostring(arguments[1]))
    elseif name == "endsWith" and type(receiver) == "string" then
      return vim.endswith(receiver, tostring(arguments[1]))
    end
    return nil, "unsupported function: " .. tostring(name)
  end
  return nil, "unsupported expression: " .. tostring(expression.kind)
end

---@param filter obsidian.base.Filter?
---@param ctx table
---@param document obsidian.base.Document
---@return boolean
---@return string?
local function matches(filter, ctx, document)
  if filter == nil then
    return true
  elseif filter.kind == "filter_expression" then
    if filter.expression == nil then
      return false, "invalid filter expression: " .. filter.source
    end
    local value, err = M.evaluate(filter.expression, ctx, document)
    return truthy(value), err
  elseif filter.operator == "not" then
    for _, child in ipairs(filter.children) do
      local value, err = matches(child, ctx, document)
      if err ~= nil then
        return false, err
      elseif not value then
        return true
      end
    end
    return false
  elseif filter.operator == "and" then
    for _, child in ipairs(filter.children) do
      local value, err = matches(child, ctx, document)
      if err ~= nil or not value then
        return false, err
      end
    end
    return true
  else
    for _, child in ipairs(filter.children) do
      local value, err = matches(child, ctx, document)
      if err ~= nil then
        return false, err
      elseif value then
        return true
      end
    end
    return false
  end
end

---@param left any
---@param right any
---@return integer -1 when left sorts first, 1 when right sorts first, otherwise 0.
local function compare_values(left, right)
  left = left == vim.NIL and nil or left
  right = right == vim.NIL and nil or right
  if vim.deep_equal(left, right) then
    return 0
  elseif left == nil then
    return 1
  elseif right == nil then
    return -1
  elseif type(left) == "number" and type(right) == "number" then
    return left < right and -1 or 1
  end
  local left_text, right_text = tostring(left):lower(), tostring(right):lower()
  if left_text == right_text then
    return 0
  end
  return left_text < right_text and -1 or 1
end

---@param document obsidian.base.Document
---@param view obsidian.base.View
---@return obsidian.base.ViewModel?
---@return string?
function M.run(document, view)
  local order = #view.order > 0 and view.order or { "file.name" }
  local columns = {}
  for _, source in ipairs(order) do
    local ref = property.parse(source)
    local metadata = document.properties[ref.canonical] or document.properties[source] or {}
    local label = type(metadata) == "table" and metadata.displayName or nil
    columns[#columns + 1] = {
      key = ref.canonical,
      label = type(label) == "string" and label or source,
    }
  end

  local filter = require("obsidian.base").effective_filter(document, view)
  local contexts = {}
  for _, ctx in ipairs(collect_candidates()) do
    local include, err = matches(filter, ctx, document)
    if err ~= nil then
      return nil, err
    elseif include then
      contexts[#contexts + 1] = ctx
    end
  end

  if #view.sort > 0 then
    for _, ctx in ipairs(contexts) do
      ctx.sort_values = {}
      for index, spec in ipairs(view.sort) do
        local value, err = get_property(ctx, property.parse(spec.property), document)
        if err ~= nil then
          return nil, err
        end
        ctx.sort_values[index] = value == nil and vim.NIL or value
      end
    end
    table.sort(contexts, function(a, b)
      for index, spec in ipairs(view.sort) do
        local comparison = compare_values(a.sort_values[index], b.sort_values[index])
        if comparison ~= 0 then
          if tostring(spec.direction or "ASC"):upper() == "DESC" then
            return comparison > 0
          end
          return comparison < 0
        end
      end
      return a.path < b.path
    end)
  end

  local rows = {}
  local count = view.limit and math.min(#contexts, math.max(0, math.floor(view.limit))) or #contexts
  for index = 1, count do
    local ctx = contexts[index]
    local values = {}
    for _, column in ipairs(columns) do
      local value, err = get_property(ctx, property.parse(column.key), document)
      if err ~= nil then
        return nil, err
      end
      values[column.key] = value == nil and vim.NIL or value
    end
    rows[#rows + 1] = { path = ctx.path, values = values }
  end

  return {
    type = assert(view.type, "view type is required"),
    name = view.name,
    columns = columns,
    rows = rows,
  }
end

function M.invalidate()
  fallback_snapshot = nil
end

M.collect_candidates = collect_candidates

return M
