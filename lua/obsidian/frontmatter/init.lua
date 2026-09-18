local M = {}
local yaml = require "obsidian.yaml"
local validator = require "obsidian.frontmatter.validator"

---@param list string[]
local function sort_by_list(list)
  return function(a, b)
    local a_idx, b_idx = nil, nil
    for i, k in ipairs(list) do
      if a == k then
        a_idx = i
      end
      if b == k then
        b_idx = i
      end
    end
    if a_idx ~= nil and b_idx ~= nil then
      return a_idx < b_idx
    elseif a_idx ~= nil then
      return true
    elseif b_idx ~= nil then
      return false
    else
      return a < b
    end
  end
end

--- Get frontmatter lines to be written
---
---@param t table<string, any>
---@param order? string[] | fun(a: any, b: any): boolean
---
---@return string[]
M.dump = function(t, order)
  local lines = { "---" }
  local order_f

  if order and type(order) == "table" and not vim.tbl_isempty(order) then
    order_f = sort_by_list(order)
  elseif order and type(order) == "function" then
    order_f = order
  end

  for _, line in ipairs(yaml.dumps_lines(t, order_f)) do
    table.insert(lines, line)
  end

  table.insert(lines, "---")

  return lines
end

--- Parse and validate info from frontmatter.
---
---@param frontmatter_lines string[] YAML body, without the boundary lines.
---@param path string|obsidian.Path?
---@param opts obsidian.yaml.ParseOpts?
---@return { id: string|?, tags: string[]|?, aliases: string[]|? }
---@return table<string, any> metadata
---@return string[] errors
---@return obsidian.yaml.Element[] elements Raw scalar occurrences before validation/normalization.
M.parse = function(frontmatter_lines, path, opts)
  local ok, data, _, elements = pcall(yaml.loads, frontmatter_lines, opts)
  if type(data) ~= "table" then
    data = {}
  end
  if not ok then
    return {}, {}, {}, {}
  end
  local metadata, ret, errors = {}, {}, {}
  for k, v in pairs(data) do
    if validator[k] ~= nil then
      local value, err = validator[k](v, tostring(path))
      if err ~= nil then
        errors[#errors + 1] = err
      else
        ret[k] = value
      end
    else
      metadata[k] = v
    end
  end

  return ret, metadata, errors, elements
end

return M
