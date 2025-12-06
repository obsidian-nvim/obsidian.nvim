local util = require "obsidian.util"

local M = {}

local function has_treesitter_parser(name)
  local res, _ = pcall(vim.treesitter.language.inspect, name)
  return res
end

if vim.fn.executable "yq" == 1 then
  M.loads = require("obsidian.yaml.yq").loads
elseif has_treesitter_parser "yaml" then
  M.loads = require("obsidian.yaml.treesitter").loads
else
  M.loads = require("obsidian.yaml.lua").loads
end

---@param s string
---@return boolean
local should_quote = function(s)
  -- TODO: this probably doesn't cover all edge cases.
  -- See https://www.yaml.info/learn/quote.html
  -- Check if it starts with a special character.
  if string.match(s, [[^["'\\[{&!-].*]]) then
    return true
  -- Check if it has a colon followed by whitespace.
  elseif string.find(s, ": ", 1, true) then
    return true
  -- Check if it's an empty string.
  elseif s == "" or string.match(s, "^[%s]+$") then
    return true
  elseif util.is_hex_color(s) then
    return true
  else
    return false
  end
end

---@return string[]
local dumps
dumps = function(x, indent, order)
  local indent_str = string.rep(" ", indent)

  if type(x) == "string" then
    if should_quote(x) then
      x = string.gsub(x, '"', '\\"')
      return { indent_str .. [["]] .. x .. [["]] }
    else
      return { indent_str .. x }
    end
  end

  if type(x) == "boolean" then
    return { indent_str .. tostring(x) }
  end

  if type(x) == "number" then
    return { indent_str .. tostring(x) }
  end

  if type(x) == "userdata" then
    return {}
  end

  if type(x) == "table" then
    local out = {}

    if util.islist(x) then
      for _, v in ipairs(x) do
        local item_lines = dumps(v, indent + 2)
        table.insert(out, indent_str .. "- " .. util.lstrip_whitespace(item_lines[1]))
        for i = 2, #item_lines do
          table.insert(out, item_lines[i])
        end
      end
    else
      -- Gather and sort keys so we can keep the order deterministic.
      local keys = {}
      for k, _ in pairs(x) do
        table.insert(keys, k)
      end
      table.sort(keys, order)
      for _, k in ipairs(keys) do
        local v = x[k]
        if type(v) == "string" or type(v) == "boolean" or type(v) == "number" then
          table.insert(out, indent_str .. tostring(k) .. ": " .. dumps(v, 0)[1])
        elseif type(v) == "table" and vim.tbl_isempty(v) then
          table.insert(out, indent_str .. tostring(k) .. ": []")
        else
          local item_lines = dumps(v, indent + 2)
          table.insert(out, indent_str .. tostring(k) .. ":")
          for _, line in ipairs(item_lines) do
            table.insert(out, line)
          end
        end
      end
    end

    return out
  end

  if type(x) == "userdata" and x == vim.NIL then
    return { "null" }
  end

  error("Can't convert object with type " .. type(x) .. " to YAML")
end

---Dump an object to YAML lines.
---@param x any
---@param order function?
---@return string[]
M.dumps_lines = function(x, order)
  return dumps(x, 0, order)
end

---Dump an object to a YAML string.
---@param x any
---@param order function|?
---@return string
M.dumps = function(x, order)
  return table.concat(dumps(x, 0, order), "\n")
end

return M
