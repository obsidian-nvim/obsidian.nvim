local M = {}
local yaml = require "obsidian.yaml"
local log = require "obsidian.log"

--- Get frontmatter lines that can be written to a buffer.
---
---@param t table<string, any>
---@param order string[] | fun(a: any, b: any): boolean
---
---@return string[]
M.dump = function(t, order)
  local new_lines = { "---" }
  local order_f

  if order and type(order) == "table" then
    local value2order = {}
    for i, v in ipairs(order) do
      value2order[v] = i
    end
    order_f = function(a, b)
      return value2order[a] < value2order[b]
    end
  elseif order and type(order) == "function" then
    order_f = order
  end

  for _, line in ipairs(yaml.dumps_lines(t, order_f)) do
    table.insert(new_lines, line)
  end

  table.insert(new_lines, "---")

  return new_lines
end

local handlder = {}

handlder.id = function(v, path)
  if type(v) == "string" or type(v) == "number" then
    return tostring(v)
  else
    log.warn("Invalid 'id' in frontmatter for " .. tostring(path))
  end
end

handlder.aliases = function(v, path)
  local aliases = {}
  if type(v) == "table" then
    for _, alias in ipairs(v) do
      if type(alias) == "string" then
        table.insert(aliases, alias)
      else
        log.warn(
          "Invalid alias value found in frontmatter for "
            .. tostring(path)
            .. ". Expected string, found "
            .. type(alias)
            .. "."
        )
      end
    end
  elseif type(v) == "string" then
    table.insert(aliases, v)
  else
    log.warn("Invalid 'aliases' in frontmatter for " .. tostring(path))
  end

  return aliases
end

handlder.tags = function(v, path)
  local tags = {}
  if type(v) == "table" then
    for _, tag in ipairs(v) do
      if type(tag) == "string" then
        table.insert(tags, tag)
      else
        log.warn(
          "Invalid tag value found in frontmatter for "
            .. tostring(path)
            .. ". Expected string, found "
            .. type(tag)
            .. "."
        )
      end
    end
  elseif type(v) == "string" then --- TODO: why not in aliases?
    tags = vim.split(v, " ")
  else
    log.warn("Invalid 'tags' in frontmatter for '%s'", path)
  end
end

---@param frontmatter string
---@return table
---@return table
M.parse = function(frontmatter, path)
  local ok, data = pcall(yaml.loads, frontmatter)
  if type(data) ~= "table" then
    data = {}
  end
  if not ok then
    return {}, {}
  end
  local metadata, ret = {}, {}
  for k, v in pairs(data) do
    if handlder[k] then
      ret[k] = handlder[k](v, path)
    else
      metadata[k] = v
      ret[k] = v
    end
  end

  return ret, metadata
end

return M
