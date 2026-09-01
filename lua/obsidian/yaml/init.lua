local util = require "obsidian.util"
local parser = require "obsidian.yaml.parser"

local yaml = {}

---Deserialize a YAML string.
---@param str string
---@return any
---@return string[]
yaml.loads = function(str)
  return parser.loads(str)
end

---@param s string
---@return boolean
local resolves_as_number = function(s)
  return tonumber(s) ~= nil
end

---@param s string
---@return boolean
local resolves_as_non_string = function(s)
  -- Quote strings that this parser, YAML 1.2, or common YAML 1.1 parsers would
  -- otherwise resolve as numbers, booleans, or nulls.
  if resolves_as_number(s) then
    return true
  end

  local lower = string.lower(s)
  return lower == "true"
    or lower == "false"
    or lower == "null"
    or lower == "~"
    or lower == "y"
    or lower == "yes"
    or lower == "n"
    or lower == "no"
    or lower == "on"
    or lower == "off"
end

---@param s string
---@return boolean
local is_date_like = function(s)
  return s:match "^%d%d%d%d[._%-]%d%d?[._%-]%d%d?$" ~= nil
    or s:match "^%d%d%d%d[._%-]%d%d?[._%-]%d%d?%s+%d%d?:%d%d$" ~= nil
    or s:match "^%d%d%d%d[._%-]%d%d?[._%-]%d%d?%s+%d%d?:%d%d:%d%d$" ~= nil
end

---@param s string
---@return boolean
local should_quote = function(s)
  -- Plain scalar rules: https://www.yaml.info/learn/quote.html
  -- We quote conservatively, but still allow backslash-starting scalars like
  -- Pandoc LaTeX header-includes (`\usepackage{...}`), where double quotes can
  -- accidentally introduce YAML escape sequences.
  if s == "" or s:match "^%s" or s:match "%s$" then
    return true
  elseif s:match "[%z\1-\8\11\12\14-\31]" then
    return true
  elseif s:match "^[-?:]%s" or s == "-" or s == "?" or s == ":" then
    return true
  elseif s:match "^[!&*{}%[%],#|>%%@`\"']" then
    return true
  elseif s:match "^%.%.%.%s*$" or s:match "^%-%-%-%s*$" then
    return true
  elseif s:find(": ", 1, true) or s:match ":$" then
    return true
  elseif s:match "%s#" then
    return true
  elseif s:match "%[%[.-%]%]" then
    return true
  elseif resolves_as_non_string(s) then
    return true
  elseif util.is_hex_color(s) then
    return true
  elseif s:match "%s" and not is_date_like(s) then
    return true
  else
    return false
  end
end

---@param s string
---@return string
local quote_string = function(s)
  if s:find("\\", 1, true) then
    return "'" .. s:gsub("'", "''") .. "'"
  end

  return '"' .. s:gsub('"', '\\"') .. '"'
end

---@param s string
---@param indent integer
---@return string[]
local function dump_string(s, indent)
  local indent_str = string.rep(" ", indent)

  -- Check if string contains newlines - use literal block syntax
  if s:find("\n", 1, true) then
    local lines = {}
    -- First line: just the literal block indicator
    table.insert(lines, "|")
    -- Subsequent lines: content with additional indent for block
    local content_indent = string.rep(" ", 2)
    for line in s:gmatch "[^\n]+" do
      table.insert(lines, content_indent .. line)
    end
    return lines
  end

  if should_quote(s) then
    return { indent_str .. quote_string(s) }
  else
    return { indent_str .. s }
  end
end

---@return string[]
local function dumps(x, indent, order)
  local indent_str = string.rep(" ", indent)

  if type(x) == "string" then
    return dump_string(x, indent)
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

    if vim.islist(x) then
      for _, v in ipairs(x) do
        local item_lines = dumps(v, indent + 2)
        if #item_lines == 0 then
          if v == vim.NIL then
            table.insert(out, indent_str .. "-")
          else
            table.insert(out, indent_str .. "- []")
          end
        else
          local first_line = item_lines[1]
          if first_line then
            table.insert(out, indent_str .. "- " .. util.lstrip_whitespace(first_line))
          end
          for i = 2, #item_lines do
            table.insert(out, item_lines[i])
          end
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
        if type(v) == "string" then
          local key_str = tostring(k)
          -- For multiline strings, we need proper indent; for simple strings use 0
          local is_multiline = v:find("\n", 1, true) ~= nil
          local str_indent = is_multiline and (#indent_str + #key_str + 2) or 0
          local str_lines = dump_string(v, str_indent)
          -- First line: key + ": " + content
          table.insert(out, indent_str .. key_str .. ": " .. str_lines[1])
          -- Subsequent lines: content with proper indent
          for i = 2, #str_lines do
            table.insert(out, indent_str .. str_lines[i])
          end
        elseif type(v) == "boolean" or type(v) == "number" then
          table.insert(out, indent_str .. tostring(k) .. ": " .. tostring(v))
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

  error("Can't convert object with type " .. type(x) .. " to YAML")
end

---Dump an object to YAML lines.
---@param x any
---@param order function?
---@return string[]
yaml.dumps_lines = function(x, order)
  return dumps(x, 0, order)
end

---Dump an object to a YAML string.
---@param x any
---@param order function|?
---@return string
yaml.dumps = function(x, order)
  return table.concat(dumps(x, 0, order), "\n")
end

return yaml
