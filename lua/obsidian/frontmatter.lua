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

---@param frontmatter string
---@return string? id
---@return string? title
---@return string[] aliases
---@return string[] tags
---@return table<string, any>? metadata
M.parse = function(frontmatter, path)
  local id, title, metadata
  local aliases, tags = {}, {}
  local ok, data = pcall(yaml.loads, frontmatter)
  if type(data) ~= "table" then
    data = {}
  end
  if not ok then
    return nil, nil, {}, {}, nil
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  for k, v in pairs(data) do
    if k == "id" then
      if type(v) == "string" or type(v) == "number" then
        id = tostring(v)
      else
        log.warn("Invalid 'id' in frontmatter for " .. tostring(path))
      end
    elseif k == "title" then
      if type(v) == "string" then
        title = v
        if metadata == nil then
          metadata = {}
        end
        metadata.title = v
      else
        log.warn("Invalid 'title' in frontmatter for " .. tostring(path))
      end
    elseif k == "aliases" then
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
    elseif k == "tags" then
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
      elseif type(v) == "string" then
        tags = vim.split(v, " ")
      else
        log.warn("Invalid 'tags' in frontmatter for '%s'", path)
      end
    else
      if metadata == nil then
        metadata = {}
      end
      metadata[k] = v
    end
  end

  return id, title, aliases, tags, metadata
end

return M
