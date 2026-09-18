local Line = require "obsidian.yaml.line"
local Range = require "obsidian.range"
local util = require "obsidian.util"
local yaml_util = require "obsidian.yaml.util"

local m = {}

---@class obsidian.yaml.ParserOpts
---@field luanil boolean
---@field default? fun(): obsidian.yaml.ParserOpts
---@field normalize? fun(opts: table): obsidian.yaml.ParserOpts
local ParserOpts = {}

m.ParserOpts = ParserOpts

---@return obsidian.yaml.ParserOpts
ParserOpts.default = function()
  return {
    luanil = false,
  }
end

---@param opts table
---@return obsidian.yaml.ParserOpts
ParserOpts.normalize = function(opts)
  ---@type obsidian.yaml.ParserOpts
  opts = vim.tbl_extend("force", ParserOpts.default(), opts)
  return opts
end

--- A scalar occurrence in the original YAML, separate from decoded metadata.
--- Paths use mapping keys and 1-based sequence indices. Repeated values remain distinct.
--- Ranges include quotes/block indicators, but exclude surrounding whitespace and comments.
--- Implicit nulls have empty ranges after the ':' or '-'.
---@class obsidian.yaml.Element
---@field kind "scalar"
---@field path (string|integer)[]
---@field value any
---@field range obsidian.Range

---@class obsidian.yaml.ParseOpts
---@field base_row integer? Document row of the first input line (default 0).

---@class obsidian.yaml.Parser
---@field opts obsidian.yaml.ParserOpts
---@field _lines obsidian.yaml.Line[]
---@field _elements obsidian.yaml.Element[]
---@field _path (string|integer)[]
local Parser = {}
Parser.__index = Parser

m.Parser = Parser

---@enum YamlType
local YamlType = {
  Scalar = "Scalar", -- a boolean, string, number, or NULL
  Mapping = "Mapping",
  Array = "Array",
  ArrayItem = "ArrayItem",
  EmptyLine = "EmptyLine",
}

m.YamlType = YamlType

---@class vim.NIL

---Create a new Parser.
---@param opts obsidian.yaml.ParserOpts|?
---@return obsidian.yaml.Parser
m.new = function(opts)
  local self = {}
  self.opts = ParserOpts.normalize(opts and opts or {})
  return setmetatable(self, Parser)
end

--- Parse YAML without discarding physical blank lines or source byte offsets.
--- The first two returns retain the decoded-value/key-order API.
---@param str string|string[] Lines exclude line endings and are not modified.
---@param opts obsidian.yaml.ParseOpts?
---@return any value
---@return string[] order
---@return obsidian.yaml.Element[] elements Scalar occurrences in source order.
Parser.parse = function(self, str, opts)
  opts = opts or {}
  local base_row = opts.base_row or 0
  assert(base_row >= 0 and base_row % 1 == 0, "base_row must be a nonnegative integer")
  local raw_lines
  if type(str) == "string" then
    raw_lines = vim.split(str, "\r?\n")
  else
    raw_lines = str
  end
  local base_indent = 0
  for _, raw_line in ipairs(raw_lines) do
    if vim.trim(yaml_util.strip_comments(vim.trim(raw_line))) ~= "" then
      base_indent = util.count_indent(raw_line)
      break
    end
  end
  ---@type obsidian.yaml.Line[]
  local lines = {}
  for i, raw_line in ipairs(raw_lines) do
    local ok, result = pcall(Line.new, raw_line, base_indent, base_row + i - 1)
    if not ok then
      error(self:_error_msg(tostring(result), i))
    end
    lines[#lines + 1] = result
  end
  self._lines, self._elements, self._path = lines, {}, {}

  -- Now iterate over the root elements, differing to `self:_parse_next()` to recurse into child elements.
  ---@type any
  local root_value = nil
  ---@type table|?
  local parent = nil
  local current_indent = 0
  local i = 1
  local order = {} ---@type string[]
  local root_item = 0
  while i <= #lines do
    local line = lines[i]
    ---@cast line -nil

    if line:is_empty() then
      -- Empty line, skip it.
      i = i + 1
    elseif line.indent == current_indent then
      local value
      local value_type
      local is_item = line.content == "-" or vim.startswith(line.content, "- ")
      if is_item then
        root_item = root_item + 1
        self._path[1] = root_item
      end
      i, value, value_type = self:_parse_next(lines, i)
      self._path[1] = nil
      if type(value) == "table" then
        local k, v = next(value)
        if k and v then
          order[#order + 1] = k
        end
      end
      assert(value_type ~= YamlType.EmptyLine, "")
      if root_value == nil and line.indent == 0 then
        -- Set the root value.
        if value_type == YamlType.ArrayItem then
          root_value = { value }
        else
          root_value = value
        end

        -- The parent must always be a table (array or mapping), so set that to the root value now
        -- if we have a table.
        if type(root_value) == "table" then
          parent = root_value
        end
      elseif parent ~= nil and vim.islist(parent) and value_type == YamlType.ArrayItem then
        -- Add value to parent array.
        parent[#parent + 1] = value
      elseif type(parent) == "table" and value_type == YamlType.Mapping then
        -- Add value to parent mapping.
        ---@cast value table
        for key, item in pairs(value) do
          -- Check for duplicate keys.
          if parent[key] ~= nil then
            error(self:_error_msg("duplicate key '" .. key .. "' found in table", i, line.content))
          else
            parent[key] = item
          end
        end
      else
        error(self:_error_msg("unexpected value", i, line.content))
      end
    else
      error(self:_error_msg("invalid indentation", i))
    end
    if not line:is_empty() then
      current_indent = line.indent
    end
  end

  return root_value, order, self._elements
end

---@param i integer
---@param col integer
---@param text string
---@param value any
---@return obsidian.yaml.Element
Parser._record_scalar = function(self, i, col, text, value)
  local row = self._lines[i].row
  local element = {
    kind = "scalar",
    path = vim.list_extend({}, self._path),
    value = value,
    range = Range.new(row, col, row, col + #text),
  }
  self._elements[#self._elements + 1] = element
  return element
end

---Parse the next single item, recursing to child blocks if necessary.
---@param self obsidian.yaml.Parser
---@param lines obsidian.yaml.Line[]
---@param i integer
---@param text string|?
---@param col integer? Byte offset of text in the original line.
---@return integer, any, string
Parser._parse_next = function(self, lines, i, text, col)
  local line = lines[i]
  ---@cast line -nil
  if text == nil then
    -- Skip empty lines.
    while line:is_empty() and i <= #lines do
      i = i + 1
      line = assert(lines[i], "unexpected end of YAML input")
    end
    if line:is_empty() then
      return i, nil, YamlType.EmptyLine
    end
    text = yaml_util.strip_comments(line.content)
  end

  col = col or line.content_col
  col = col + #text - #util.lstrip_whitespace(text)
  text = vim.trim(text)
  local _, ok, value

  -- First just check for a string enclosed in quotes.
  if yaml_util.has_enclosing_chars(text) then
    _, _, value = self:_parse_string(i, text)
    self:_record_scalar(i, col, text, value)
    return i + 1, value, YamlType.Scalar
  end

  -- Check for array item, like `- foo`.
  ok, i, value = self:_try_parse_array_item(lines, i, text, col)
  if ok then
    return i, value, YamlType.ArrayItem
  end

  -- Check for a block string field, like `foo: |`.
  ok, i, value = self:_try_parse_block_string(lines, i, text, col)
  if ok then
    return i, value, YamlType.Mapping
  end

  -- Check for any other `key: value` fields.
  ok, i, value = self:_try_parse_field(lines, i, text, col)
  if ok then
    return i, value, YamlType.Mapping
  end

  -- Otherwise we have an inline value.
  local value_type
  value, value_type = self:_parse_inline_value(i, text, col)
  return i + 1, value, value_type
end

---@return vim.NIL|nil
Parser._new_null = function(self)
  if self.opts.luanil then
    return nil
  else
    return vim.NIL
  end
end

---@param msg string
---@param line_num integer
---@param line_text string|?
---@return string
Parser._error_msg = function(_, msg, line_num, line_text)
  local full_msg = "[line=" .. tostring(line_num) .. "] " .. msg
  if line_text ~= nil then
    full_msg = full_msg .. " (text='" .. line_text .. "')"
  end
  return full_msg
end

local YAML_KEY_REGEX = "([a-zA-Z0-9_-()/]+[a-zA-Z0-9_()/ -]*)"
local YAML_MAPPING_START_REGEX = string.format("%s:$", YAML_KEY_REGEX)
local YAML_MAPPING_INLINE_REGEX = string.format("%s: (.*)", YAML_KEY_REGEX)

---@param self obsidian.yaml.Parser
---@param i integer
---@param lines obsidian.yaml.Line[]
---@param text string|?
---@param col integer?
---@return boolean, integer, any
Parser._try_parse_field = function(self, lines, i, text, col)
  local line = lines[i]
  ---@cast line -nil
  text = text and text or yaml_util.strip_comments(line.content)
  col = col or line.content_col

  local _, key, value

  -- First look for start of mapping, array, block, etc, e.g. 'foo:'
  _, _, key = string.find(text, YAML_MAPPING_START_REGEX)
  if not key then
    -- Then try inline field, e.g. 'foo: bar'
    _, _, key, value = string.find(text, YAML_MAPPING_INLINE_REGEX)
  end

  if key == nil then
    return false, i, nil
  end
  local value_col = value and col + #text - #value or col + #text
  if value then
    value_col = value_col + #value - #util.lstrip_whitespace(value)
    value = vim.trim(value)
  end
  if value == "" then
    value = nil
  end
  self._path[#self._path + 1] = key

  if value ~= nil then
    -- This is a mapping, e.g. `foo: 1`.
    local out = {}
    value = self:_parse_inline_value(i, value, value_col)
    local element = self._elements[#self._elements]
    local j = i + 1
    -- Check for multi-line string here.
    local next_content = j
    while lines[next_content] and lines[next_content]:is_empty() do
      next_content = next_content + 1
    end
    local next_line = lines[next_content]
    if type(value) == "string" and next_line ~= nil and next_line.indent > line.indent then
      local continuation_indent = next_line.indent
      j = next_content
      ---@diagnostic disable-next-line: preferred-local-alias
      while next_line ~= nil and (next_line:is_empty() or next_line.indent == continuation_indent) do
        local next_value_str = yaml_util.strip_comments(next_line.content)
        if string.len(next_value_str) > 0 then
          local next_value = self:_parse_inline_value(j, next_value_str, next_line.content_col)
          if type(next_value) ~= "string" then
            error(self:_error_msg("expected a string, found " .. type(next_value), j, next_line.content))
          end
          value = value .. " " .. next_value
          local continuation = table.remove(self._elements)
          element.value = value
          element.range = Range.new(
            element.range.start_row,
            element.range.start_col,
            continuation.range.end_row,
            continuation.range.end_col
          )
        end
        j = j + 1
        next_line = lines[j]
      end
    end
    out[key] = value
    self._path[#self._path] = nil
    return true, j, out
  else
    local out = {}
    local j = i + 1
    while lines[j] and lines[j]:is_empty() do
      j = j + 1
    end
    local next_line = lines[j]
    if
      next_line ~= nil
      and next_line.indent >= line.indent
      and (next_line.content == "-" or vim.startswith(next_line.content, "- "))
    then
      -- This is the start of an array.
      local array
      j, array = self:_parse_array(lines, j)
      out[key] = array
    elseif next_line ~= nil and next_line.indent > line.indent then
      -- This is the start of a mapping.
      local mapping
      j, mapping = self:_parse_mapping(j, lines)
      out[key] = mapping
    else
      -- This is an implicit null field.
      out[key] = self:_new_null()
      self:_record_scalar(i, col + #text, "", out[key])
    end
    self._path[#self._path] = nil
    return true, j, out
  end
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param lines obsidian.yaml.Line[]
---@param text string|?
---@param col integer?
---@return boolean, integer, any
Parser._try_parse_block_string = function(self, lines, i, text, col)
  local line = lines[i]
  ---@cast line -nil
  text = text and text or yaml_util.strip_comments(line.content)
  col = col or line.content_col
  local _, _, block_key = string.find(text, "^([a-zA-Z0-9_-]+):%s*|%s*$")
  if block_key ~= nil then
    local block_lines = {}
    local j = i + 1
    local next_line = lines[j]
    if next_line == nil then
      error(self:_error_msg("expected another line", i, text))
    end
    local first_content = j
    while lines[first_content] and vim.trim(lines[first_content].source) == "" do
      first_content = first_content + 1
    end
    local block_indent = math.max(line.indent + 1, lines[first_content] and lines[first_content].indent or 0)
    while j <= #lines do
      next_line = lines[j]
      ---@diagnostic disable-next-line: preferred-local-alias
      if next_line ~= nil and (vim.trim(next_line.source) == "" or next_line.indent >= block_indent) then
        j = j + 1
        table.insert(block_lines, util.lstrip_whitespace(next_line.raw_content, block_indent))
      else
        break
      end
    end
    local out = {}
    out[block_key] = table.concat(block_lines, "\n")
    self._path[#self._path + 1] = block_key
    local indicator_col = col + assert(text:find("|", 1, true)) - 1
    local element = self:_record_scalar(i, indicator_col, "|", out[block_key])
    if j > i + 1 then
      local last_line = assert(lines[j - 1], "missing final block scalar line")
      element.range = Range.new(line.row, indicator_col, last_line.row, #last_line.source)
    end
    self._path[#self._path] = nil
    return true, j, out
  else
    return false, i, nil
  end
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param lines obsidian.yaml.Line[]
---@param text string|?
---@param col integer?
---@return boolean, integer, any
Parser._try_parse_array_item = function(self, lines, i, text, col)
  local line = lines[i]
  ---@cast line -nil
  text = text and text or yaml_util.strip_comments(line.content)
  col = col or line.content_col
  if text == "-" then
    -- Bare dash is a null array item.
    local value = self:_new_null()
    self:_record_scalar(i, col + 1, "", value)
    return true, i + 1, value
  elseif vim.startswith(text, "- ") then
    local array_item_str = text:sub(3)
    local value
    -- Check for null entry.
    if array_item_str == "" then
      value = self:_new_null()
      self:_record_scalar(i, col + 2, "", value)
      i = i + 1
    else
      local item_col = col + 2 + #array_item_str - #util.lstrip_whitespace(array_item_str)
      i, value = self:_parse_next(lines, i, vim.trim(array_item_str), item_col)
    end
    return true, i, value
  else
    return false, i, nil
  end
end

---@param self obsidian.yaml.Parser
---@param lines obsidian.yaml.Line[]
---@param i integer
---@return integer, any[]
Parser._parse_array = function(self, lines, i)
  local out = {}
  local first_line = lines[i]
  ---@cast first_line -nil
  local item_indent = first_line.indent
  local item_index = 0
  while i <= #lines do
    local line = lines[i]
    ---@cast line -nil
    if line.indent == item_indent and (line.content == "-" or vim.startswith(line.content, "- ")) then
      local is_array_item, value
      item_index = item_index + 1
      self._path[#self._path + 1] = item_index
      is_array_item, i, value = self:_try_parse_array_item(lines, i)
      self._path[#self._path] = nil
      assert(is_array_item, "not an array item")
      out[#out + 1] = value
    elseif line:is_empty() then
      i = i + 1
    else
      break
    end
  end
  if vim.tbl_isempty(out) then
    error(self:_error_msg("tried to parse an array but didn't find any entries", i))
  end
  return i, out
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param lines obsidian.yaml.Line[]
---@return integer, table
Parser._parse_mapping = function(self, i, lines)
  local out = {}
  local first_line = lines[i]
  ---@cast first_line -nil
  local item_indent = first_line.indent
  while i <= #lines do
    local line = lines[i]
    ---@cast line -nil
    if line:is_empty() then
      i = i + 1
    elseif line.indent == item_indent then
      local value, value_type
      i, value, value_type = self:_parse_next(lines, i)
      if value_type == YamlType.Mapping then
        for key, item in pairs(value) do
          -- Check for duplicate keys.
          if out[key] ~= nil then
            error(self:_error_msg("duplicate key '" .. key .. "' found in table", i))
          else
            out[key] = item
          end
        end
      else
        error(self:_error_msg("unexpected value found in table", i))
      end
    else
      break
    end
  end
  if vim.tbl_isempty(out) then
    error(self:_error_msg("tried to parse a mapping but didn't find any entries to parse", i))
  end
  return i, out
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param text string
---@param col integer Byte offset of text before trimming.
---@return any, string
Parser._parse_inline_value = function(self, i, text, col)
  col = col + #text - #util.lstrip_whitespace(text)
  text = vim.trim(text)
  if not text:match "%[%[.-%]%]" and not yaml_util.has_enclosing_chars(text) then
    for _, entry in ipairs {
      { self._parse_inline_array, YamlType.Array },
      { self._parse_inline_mapping, YamlType.Mapping },
    } do
      local parse_func, parse_type = unpack(entry)
      local ok, errmsg, value = parse_func(self, i, text, col)
      if ok then
        return value, parse_type
      elseif errmsg then
        error(errmsg)
      end
    end
  end
  for _, parse_func in ipairs { self._parse_number, self._parse_null, self._parse_boolean, self._parse_string } do
    local ok, errmsg, value = parse_func(self, i, text)
    if ok then
      self:_record_scalar(i, col, text, value)
      return value, YamlType.Scalar
    elseif errmsg then
      error(errmsg)
    end
  end
  error(self:_error_msg("unable to parse", i))
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param text string
---@param col integer
---@return boolean, string|?, any[]|?
Parser._parse_inline_array = function(self, i, text, col)
  local str
  if vim.startswith(text, "[") then
    str = string.sub(text, 2)
  else
    return false, nil, nil
  end

  if vim.endswith(str, "]") then
    str = string.sub(str, 1, -2)
  else
    return false, nil, nil
  end

  local out = {}
  local item_index = 0
  str = util.lstrip_whitespace(str)
  while string.len(str) > 0 do
    local item_col = col + #text - 1 - #str
    local item_str
    if vim.startswith(str, "[") then
      -- Nested inline array.
      item_str, str = yaml_util.next_item(str, { "]" }, true)
    elseif vim.startswith(str, "{") then
      -- Nested inline mapping.
      item_str, str = yaml_util.next_item(str, { "}" }, true)
    else
      -- Regular item.
      item_str, str = yaml_util.next_item(str, { "," }, false)
    end
    if item_str == nil then
      return false, self:_error_msg("invalid inline array", i, text), nil
    end
    item_index = item_index + 1
    self._path[#self._path + 1] = item_index
    out[#out + 1] = self:_parse_inline_value(i, item_str, item_col)
    self._path[#self._path] = nil

    str = util.lstrip_whitespace(str)
    if vim.startswith(str, ",") then
      str = string.sub(str, 2)
    end
    str = util.lstrip_whitespace(str)
  end

  return true, nil, out
end

---@param self obsidian.yaml.Parser
---@param i integer
---@param text string
---@param col integer
---@return boolean, string|?, table|?
Parser._parse_inline_mapping = function(self, i, text, col)
  local str
  if vim.startswith(text, "{") then
    str = string.sub(text, 2)
  else
    return false, nil, nil
  end

  if vim.endswith(str, "}") then
    str = string.sub(str, 1, -2)
  else
    return false, self:_error_msg("invalid inline mapping", i, text), nil
  end

  local out = {}
  str = util.lstrip_whitespace(str)
  while string.len(str) > 0 do
    -- Parse the key.
    local key_str
    key_str, str = yaml_util.next_item(str, { ":" }, false)
    if key_str == nil then
      return false, self:_error_msg("invalid inline mapping", i, text), nil
    end
    local _, _, key = self:_parse_string(i, key_str)

    -- Parse the value.
    str = util.lstrip_whitespace(str)
    local value_col = col + #text - 1 - #str
    local value_str
    if vim.startswith(str, "[") then
      -- Nested inline array.
      value_str, str = yaml_util.next_item(str, { "]" }, true)
    elseif vim.startswith(str, "{") then
      -- Nested inline mapping.
      value_str, str = yaml_util.next_item(str, { "}" }, true)
    else
      -- Regular item.
      value_str, str = yaml_util.next_item(str, { "," }, false)
    end
    if value_str == nil then
      return false, self:_error_msg("invalid inline mapping", i, text), nil
    end
    self._path[#self._path + 1] = key
    local value = self:_parse_inline_value(i, value_str, value_col)
    self._path[#self._path] = nil
    if out[key] == nil then
      out[key] = value
    else
      return false, self:_error_msg("duplicate key '" .. key .. "' found in inline mapping", i, text), nil
    end

    str = util.lstrip_whitespace(str)
    if vim.startswith(str, ",") then
      str = util.lstrip_whitespace(string.sub(str, 2))
    end
  end

  return true, nil, out
end

---@param text string
---@return boolean, string|?, string
Parser._parse_string = function(_, _, text)
  text = vim.trim(text)
  if vim.startswith(text, [["]]) and vim.endswith(text, [["]]) then
    -- When the text is enclosed with double quotes, un-escape the escapes this
    -- dumper emits.
    text = yaml_util.strip_enclosing_chars(text)
    text = string.gsub(text, vim.pesc [[\"]], [["]])
  elseif vim.startswith(text, [[']]) and vim.endswith(text, [[']]) then
    -- YAML single-quoted strings escape a single quote as two single quotes.
    text = yaml_util.strip_enclosing_chars(text)
    text = string.gsub(text, "''", "'")
  else
    text = yaml_util.strip_enclosing_chars(text)
  end
  return true, nil, text
end

---Parse a string value.
---@param self obsidian.yaml.Parser
---@param text string
---@return string
Parser.parse_string = function(self, text)
  local _, _, str = self:_parse_string(1, yaml_util.strip_comments(text))
  return str
end

---Check if a string is NaN
---
---@param v any
---@return boolean
local is_nan = function(v)
  return tostring(v) == tostring(0 / 0)
end

---@param text string
---@return boolean, string|?, number|?
Parser._parse_number = function(_, _, text)
  local out = tonumber(text)
  if out == nil or is_nan(out) then
    return false, nil, nil
  else
    return true, nil, out
  end
end

---Parse a number value.
---@param self obsidian.yaml.Parser
---@param text string
---@return number
Parser.parse_number = function(self, text)
  local ok, errmsg, res = self:_parse_number(1, vim.trim(yaml_util.strip_comments(text)))
  if not ok then
    errmsg = errmsg and errmsg or self:_error_msg("failed to parse a number", 1, text)
    error(errmsg)
  else
    assert(res ~= nil, "nil return in parse number")
    return res
  end
end

---@param text string
---@return boolean, string|?, boolean|?
Parser._parse_boolean = function(_, _, text)
  if text == "true" then
    return true, nil, true
  elseif text == "false" then
    return true, nil, false
  else
    return false, nil, nil
  end
end

---Parse a boolean value.
---@param self obsidian.yaml.Parser
---@param text string
---@return boolean
Parser.parse_boolean = function(self, text)
  local ok, errmsg, res = self:_parse_boolean(1, vim.trim(yaml_util.strip_comments(text)))
  if not ok then
    errmsg = errmsg and errmsg or self:_error_msg("failed to parse a boolean", 1, text)
    error(errmsg)
  else
    assert(res ~= nil, "nil return in parse boolean")
    return res
  end
end

---@param text string
---@return boolean, string|?, vim.NIL|nil
Parser._parse_null = function(self, _, text)
  if text == "null" or text == "~" or text == "" then
    return true, nil, self:_new_null()
  else
    return false, nil, nil
  end
end

---Parse a NULL value.
---@param self obsidian.yaml.Parser
---@param text string
---@return vim.NIL|nil
Parser.parse_null = function(self, text)
  local ok, errmsg, res = self:_parse_null(1, vim.trim(yaml_util.strip_comments(text)))
  if not ok then
    errmsg = errmsg and errmsg or self:_error_msg("failed to parse a null value", 1, text)
    error(errmsg)
  else
    return res
  end
end

---Deserialize a YAML string.
---@param str string|string[]
---@param opts obsidian.yaml.ParseOpts?
---@return any, string[], obsidian.yaml.Element[]
m.loads = function(str, opts)
  local parser = m.new()
  return parser:parse(str, opts)
end

return m
