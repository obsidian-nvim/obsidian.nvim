local M = {}
local yaml = require "obsidian.yaml"
local log = require "obsidian.log"
local validater = require "obsidian.frontmatter.validater"

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
    if a_idx and b_idx then
      return a_idx < b_idx
    elseif a_idx then
      return true
    elseif b_idx then
      return false
    else
      return a < b
    end
  end
end

--- Get frontmatter lines to be written
---
---@param t table<string, any>
---@param order string[] | fun(a: any, b: any): boolean
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
---@param frontmatter_lines string[]
---@return { id: string, tags: string[], aliases: string[] }
---@return table<string, any>
M.parse = function(frontmatter_lines, path)
  local frontmatter = table.concat(frontmatter_lines, "\n")
  local ok, data = pcall(yaml.loads, frontmatter)
  if type(data) ~= "table" then
    data = {}
  end
  if not ok then
    return {}, {}
  end
  local metadata, ret = {}, {}
  for k, v in pairs(data) do
    if validater[k] then
      local value, err = validater[k](v, path)
      if err ~= nil then
        log.warn(err)
      else
        ret[k] = value
      end
    else
      metadata[k] = v
    end
  end

  return ret, metadata
end

return M
