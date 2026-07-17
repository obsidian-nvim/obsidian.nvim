local M = {}

local renderers = {}

---@param value any
---@return string
local function format_value(value)
  if value == nil or value == vim.NIL then
    return ""
  elseif type(value) == "boolean" or type(value) == "number" or type(value) == "string" then
    local text = tostring(value):gsub("\r\n", "<br>"):gsub("\n", "<br>")
    return text
  elseif type(value) == "table" and vim.islist(value) then
    local items = {}
    for _, item in ipairs(value) do
      items[#items + 1] = format_value(item)
    end
    return table.concat(items, ", ")
  elseif type(value) == "table" then
    local ok, encoded = pcall(vim.json.encode, value)
    return ok and encoded or vim.inspect(value)
  end
  return tostring(value)
end

---@param path string
---@param label string
---@return string
local function note_link(path, label)
  local target = path
  local root = vim.fs.normalize(tostring(Obsidian.dir)):gsub("/+$", "")
  path = vim.fs.normalize(path)
  if vim.startswith(path, root .. "/") then
    target = path:sub(#root + 2)
  end
  target = target:gsub("%.[^.]+$", "")
  return "[[" .. target .. "|" .. label .. "]]"
end

---@param row obsidian.base.Row
---@param column obsidian.base.Column
---@return string
local function cell(row, column)
  local value = format_value(row.values[column.key])
  if column.key == "file.name" then
    return note_link(row.path, value)
  end
  return value
end

---@param value string
---@return string
local function table_escape(value)
  return value:gsub("|", "\\|")
end

---@param model obsidian.base.ViewModel
---@return string[]
local function render_table(model)
  local header = {}
  local separator = {}
  for _, column in ipairs(model.columns) do
    header[#header + 1] = table_escape(tostring(column.label))
    separator[#separator + 1] = "---"
  end
  local lines = {
    "| " .. table.concat(header, " | ") .. " |",
    "| " .. table.concat(separator, " | ") .. " |",
  }
  for _, row in ipairs(model.rows) do
    local values = {}
    for _, column in ipairs(model.columns) do
      values[#values + 1] = table_escape(cell(row, column))
    end
    lines[#lines + 1] = "| " .. table.concat(values, " | ") .. " |"
  end
  return lines
end

---@param model obsidian.base.ViewModel
---@return string[]
local function render_list(model)
  if #model.rows == 0 then
    return { "- _No results_" }
  end
  local lines = {}
  for _, row in ipairs(model.rows) do
    local values = {}
    for _, column in ipairs(model.columns) do
      local value = cell(row, column)
      if value ~= "" then
        values[#values + 1] = value
      end
    end
    lines[#lines + 1] = "- " .. table.concat(values, " — ")
  end
  return lines
end

---@param view_type string
---@param renderer fun(model: obsidian.base.ViewModel): string[]
function M.register(view_type, renderer)
  assert(type(view_type) == "string" and view_type ~= "", "view renderer requires a type")
  assert(type(renderer) == "function", "view renderer must be a function")
  renderers[view_type] = renderer
end

---@param model obsidian.base.ViewModel
---@return string[]?
---@return string?
function M.render(model)
  local renderer = renderers[model.type]
  if renderer == nil then
    return nil, 'no renderer installed for view type "' .. model.type .. '"'
  end
  local ok, lines = pcall(renderer, model)
  if not ok then
    return nil, tostring(lines)
  end
  return lines
end

M.register("table", render_table)
M.register("list", render_list)
M.format_value = format_value
M._renderers = renderers

return M
