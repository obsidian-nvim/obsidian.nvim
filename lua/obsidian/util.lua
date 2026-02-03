local compat = require "obsidian.compat"
local ts, string, table = vim.treesitter, string, table
local util = {}

setmetatable(util, {
  __index = function(_, k)
    return require("obsidian.api")[k] or require("obsidian.builtin")[k]
  end,
})

-------------------
--- File tools ----
-------------------

---@param file string
---@param contents string
util.write_file = function(file, contents)
  local fd = assert(io.open(file, "w+"))
  fd:write(contents)
  fd:close()
end

-------------------
--- Table tools ---
-------------------

---Check if an object is an array-like table.
--- TODO: after 0.12 replace with vim.islist
---
---@param t any
---@return boolean
util.islist = function(t)
  return compat.is_list(t)
end

---Return a new list table with only the unique values of the original table.
---
---@param t table
---@return any[]
util.tbl_unique = function(t)
  local found = {}
  for _, val in pairs(t) do
    found[val] = true
  end
  return vim.tbl_keys(found)
end

--------------------
--- String Tools ---
--------------------

---Iterate over all matches of 'pattern' in 's'. 'gfind' is to 'find' as 'gsub' is to 'sub'.
---@param s string
---@param pattern string
---@param init integer|?
---@param plain boolean|?
util.gfind = function(s, pattern, init, plain)
  init = init and init or 1

  return function()
    if init < #s then
      local m_start, m_end = string.find(s, pattern, init, plain)
      if m_start ~= nil and m_end ~= nil then
        init = m_end + 1
        return m_start, m_end
      end
    end
    return nil
  end
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

--- Encode a string into URL-safe version.
---
---@param str string
---@param opts { keep_path_sep: boolean|? }|?
---
---@return string
util.urlencode = function(str, opts)
  opts = opts or {}
  local url = str
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([%(%)%*%?%[%]%$\"':<>|\\'{}])", char_to_hex)
  if not opts.keep_path_sep then
    url = url:gsub("/", char_to_hex)
  end

  -- Spaces in URLs are always safely encoded with `%20`, but not always safe
  -- with `+`. For example, `+` in a query param's value will be interpreted
  -- as a literal plus-sign if the decoder is using JavaScript's `decodeURI`
  -- function.
  url = url:gsub(" ", "%%20")
  return url
end

util.is_hex_color = function(s)
  return (s:match "^#%x%x%x$" or s:match "^#%x%x%x%x$" or s:match "^#%x%x%x%x%x%x$" or s:match "^#%x%x%x%x%x%x%x%x$")
    ~= nil
end

---Match the case of 'key' to the given 'prefix' of the key.
---
---@param prefix string
---@param key string
---@return string|?
util.match_case = function(prefix, key)
  local out_chars = {}
  for i = 1, string.len(key) do
    local c_key = string.sub(key, i, i)
    local c_pre = string.sub(prefix, i, i)
    if c_pre:lower() == c_key:lower() then
      table.insert(out_chars, c_pre)
    elseif c_pre:len() > 0 then
      return nil
    else
      table.insert(out_chars, c_key)
    end
  end
  return table.concat(out_chars, "")
end

---@param s string
---@return string|? scheme
---@return string|? rest
local function get_uri_scheme(s)
  -- scheme per RFC-ish: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
  local scheme, rest = s:match "^([%a][%w+%-%.]*):(.*)$"
  if not scheme or not rest then
    return nil
  end

  -- Avoid treating Windows drive letters as schemes: "C:\foo" or "C:/foo"
  if #scheme == 1 and rest:match "^[\\/]." then
    return nil
  end

  return scheme:lower(), rest
end

---@param s string
---@return boolean is_uri
---@return string|? scheme
util.is_uri = function(s)
  local scheme = get_uri_scheme(s)
  if scheme then
    return true, scheme
  else
    return false, nil
  end
end

-- This function removes a single backslash within double square brackets
util.unescape_single_backslash = function(text)
  return text:gsub("(%[%[[^\\]+)\\(%|[^\\]+]])", "%1%2")
end

---Count the indentation of a line.
---@param str string
---@return integer
util.count_indent = function(str)
  local indent = 0
  for i = 1, #str do
    local c = string.sub(str, i, i)
    -- space or tab both count as 1 indent
    if c == " " or c == "	" then
      indent = indent + 1
    else
      break
    end
  end
  return indent
end

---Check if a string is only whitespace.
---@param str string
---@return boolean
util.is_whitespace = function(str)
  return string.match(str, "^%s+$") ~= nil
end

---Strip whitespace from the right end of a string.
---@param str string
---@return string
util.rstrip_whitespace = function(str)
  str = string.gsub(str, "%s+$", "")
  return str
end

---Strip whitespace from the left end of a string.
---@param str string
---@param limit integer|?
---@return string
util.lstrip_whitespace = function(str, limit)
  if limit ~= nil then
    local num_found = 0
    while num_found < limit do
      str = string.gsub(str, "^%s", "")
      num_found = num_found + 1
    end
  else
    str = string.gsub(str, "^%s+", "")
  end
  return str
end

--------------------
--- Date helpers ---
--------------------

---Determines if the given date is a working day (not weekend)
---
---@param time integer
---
---@return boolean
util.is_working_day = function(time)
  local is_saturday = (os.date("%w", time) == "6")
  local is_sunday = (os.date("%w", time) == "0")
  return not (is_saturday or is_sunday)
end

--- Returns the previous day from given time
---
--- @param time integer
--- @return integer
util.previous_day = function(time)
  return time - (24 * 60 * 60)
end
---
--- Returns the next day from given time
---
--- @param time integer
--- @return integer
util.next_day = function(time)
  return time + (24 * 60 * 60)
end

---Determines the last working day before a given time
---
---@param time integer
---@return integer
util.working_day_before = function(time)
  local previous_day = util.previous_day(time)
  if util.is_working_day(previous_day) then
    return previous_day
  else
    return util.working_day_before(previous_day)
  end
end

---Determines the next working day before a given time
---
---@param time integer
---@return integer
util.working_day_after = function(time)
  local next_day = util.next_day(time)
  if util.is_working_day(next_day) then
    return next_day
  else
    return util.working_day_after(next_day)
  end
end

---Check if a string is a checkbox list item
---
---Supported checboox lists:
--- - [ ] foo
--- - [x] foo
--- + [x] foo
--- * [ ] foo
--- 1. [ ] foo
--- 1) [ ] foo
---
---@param s string
---@return boolean
util.is_checkbox = function(s)
  -- - [ ] and * [ ] and + [ ]
  if string.match(s, "%s*[-+*]%s+%[.%]") ~= nil then
    return true
  end
  -- 1. [ ] and 1) [ ]
  if string.match(s, "%s*%d+[%.%)]%s+%[.%]") ~= nil then
    return true
  end
  return false
end

util.parse_tags = require("obsidian.parse.tags").parse_tags

---@param link string
---@param opts { strip: boolean|?, exclude: obsidian.search.RefTypes[], link_type: obsidian.search.RefTypes|? }|?
---@return string|? link_location
---@return string|? link_name
---@return obsidian.search.RefTypes|? link_type
util.parse_link = function(link, opts)
  local search = require "obsidian.search"

  opts = opts and opts or {}
  -- vim.validate("opts.strip", opts.strip, "boolean", true)

  local link_type = opts.link_type
  if link_type == nil then
    for _, match in ipairs(search.find_refs(link, { exclude = { "Tag" } })) do
      local _, _, m_type = unpack(match)
      link_type = m_type
      break
    end
  end

  if link_type == nil then
    return nil
  end

  local link_location, link_name
  if link_type == "Markdown" then
    link_location = link:gsub("^%[(.-)%]%((.*)%)$", "%2")
    link_name = link:gsub("^%[(.-)%]%((.*)%)$", "%1")
  elseif link_type == "WikiWithAlias" then
    link = util.unescape_single_backslash(link)
    -- remove boundary brackets, e.g. '[[XXX|YYY]]' -> 'XXX|YYY'
    link = link:sub(3, #link - 2)
    -- split on the "|"
    local split_idx = link:find "|"
    link_location = link:sub(1, split_idx - 1)
    link_name = link:sub(split_idx + 1)
  elseif link_type == "Wiki" then
    -- remove boundary brackets, e.g. '[[YYY]]' -> 'YYY'
    link = link:sub(3, #link - 2)
    link_location = link
    link_name = link
  elseif link_type == "BlockID" then
    link_location = util.standardize_block(link)
    link_name = link
  else
    error("not implemented for " .. link_type)
  end

  if vim.startswith(link_location, "#^") then
    if vim.startswith(link_name, "#^") then
      link_name = link_name:sub(3)
    end
    return link_location:lower(), link_name, "BlockLink" -- location is lower for lookup, name is preserved with the original case
  elseif vim.startswith(link_location, "#") then
    if vim.startswith(link_name, "#") then
      link_name = link_name:sub(2)
    end
    return link_location:lower(), link_name, "HeaderLink" -- location is lower for lookup, name is preserved with the original case
  end

  if opts.strip then
    link_location = util.strip_anchor_links(link_location)
    link_location = util.strip_block_links(link_location)
  end

  return link_location, link_name, link_type
end

--- Replace references of the form '[[xxx|xxx]]', '[[xxx]]', or '[xxx](xxx)' with their title.
---
---@param s string
---
---@return string
util.replace_refs = function(s)
  local out, _ = string.gsub(s, "%[%[[^%|%]]+%|([^%]]+)%]%]", "%1")
  out, _ = out:gsub("%[%[([^%]]+)%]%]", "%1")
  out, _ = out:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  return out
end

------------------------------------
-- Miscellaneous helper functions --
------------------------------------
---@param anchor obsidian.note.HeaderAnchor
---@return string
util.format_anchor_label = function(anchor)
  return string.format(" ❯ %s", anchor.header)
end

-- We are very loose here because obsidian allows pretty much anything
-- One trailing anchor segment: "#" + at least 1 char that is not "#"
local ANCHOR_SEGMENT_PATTERN = "#[^#]+$"

util.BLOCK_PATTERN = "%^[%w%d][%w%d-]*"

util.BLOCK_LINK_PATTERN = "#" .. util.BLOCK_PATTERN

util.strip_anchor_links = function(line)
  local parts = {}

  while true do
    local s, e = line:find(ANCHOR_SEGMENT_PATTERN)
    if not s then
      break
    end

    -- Prepend this segment so "#H1#H2" stays in order.
    table.insert(parts, 1, line:sub(s, e))

    -- Remove the matched segment from the end.
    line = line:sub(1, s - 1)
  end

  if #parts == 0 then
    return line, nil
  end

  local anchor = table.concat(parts, "")
  return line, util.standardize_anchor(anchor)
end

--- Parse a block line from a line.
---
---@param line string
---
---@return string|?
util.parse_block = function(line)
  local block_match = string.match(line, util.BLOCK_PATTERN .. "$")
  return block_match
end

--- Strip block links from a line.
---@param line string
---@return string, string|?
util.strip_block_links = function(line)
  local block_match = string.match(line, util.BLOCK_LINK_PATTERN .. "$")
  if block_match then
    line = string.sub(line, 1, -block_match:len() - 1)
  end
  return line, block_match
end

--- Standardize a block identifier.
---@param block_id string
---@return string
util.standardize_block = function(block_id)
  if vim.startswith(block_id, "#") then
    block_id = string.sub(block_id, 2)
  end

  if not vim.startswith(block_id, "^") then
    block_id = "^" .. block_id
  end

  return block_id
end

--- Check if a line is a markdown header.
---@param line string
---@return boolean
util.is_header = function(line)
  if string.match(line, "^#+%s+[%w]+") then
    return true
  else
    return false
  end
end

--- Get the header level of a line.
---@param line string
---@return integer
util.header_level = function(line)
  local headers, match_count = string.gsub(line, "^(#+)%s+[%w]+.*", "%1")
  if match_count > 0 then
    return string.len(headers)
  else
    return 0
  end
end

---@param line string
---@return { header: string, level: integer, anchor: string }|?
util.parse_header = function(line)
  local header_start, header = string.match(line, "^(#+)%s+([^%s]+.*)$")
  if header_start and header then
    header = vim.trim(header)
    return {
      header = vim.trim(header),
      level = string.len(header_start),
      anchor = util.header_to_anchor(header),
    }
  else
    return nil
  end
end

--- Standardize a header anchor link.
---
---@param anchor string
---
---@return string
util.standardize_anchor = function(anchor)
  -- Lowercase everything.
  anchor = string.lower(anchor)
  -- Replace whitespace with "-".
  anchor = string.gsub(anchor, "%s", "-")
  -- Remove every non-alphanumeric character.
  anchor = string.gsub(anchor, "[^#%w\128-\255_-]", "")
  return anchor
end

--- Transform a markdown header into an link, e.g. "# Hello World" -> "#hello-world".
---
---@param header string
---
---@return string
util.header_to_anchor = function(header)
  -- Remove leading '#' and strip whitespace.
  local anchor = vim.trim(string.gsub(header, [[^#+%s+]], ""))
  return util.standardize_anchor("#" .. anchor)
end

---@alias datetime_cadence "daily"

--- Parse possible relative date macros like '@tomorrow'.
---
---@param macro string
---
---@return { macro: string, offset: integer, cadence: datetime_cadence }[]
util.resolve_date_macro = function(macro)
  ---@type { macro: string, offset: integer, cadence: datetime_cadence }[]
  local out = {}
  for m, offset_days in pairs { today = 0, tomorrow = 1, yesterday = -1 } do
    m = "@" .. m
    if vim.startswith(m, macro) then
      out[#out + 1] = { macro = m, offset = offset_days, cadence = "daily" }
    end
  end
  return out
end

--- Check if a string contains invalid characters.
---
--- @param fname string
---
--- @return boolean
util.contains_invalid_characters = function(fname)
  local invalid_chars = "#^%[%]|"
  return string.find(fname, "[" .. invalid_chars .. "]") ~= nil
end

---Higher order function, make sure a function is called with complete lines
---@param fn fun(string)?
---@return fun(string)
util.buffer_fn = function(fn)
  if not fn then
    return function() end
  end
  local buffer = ""
  return function(data)
    buffer = buffer .. data
    local lines = vim.split(buffer, "\n")
    if #lines > 1 then
      for i = 1, #lines - 1 do
        fn(lines[i])
      end
      buffer = lines[#lines] or "" -- Store remaining partial line
    end
  end
end

---@param event string
---@param callback fun(...)
---@param ... any
---@return boolean success
util.fire_callback = function(event, callback, ...)
  local log = require "obsidian.log"
  if not callback then
    return false
  end
  local ok, err = pcall(callback, ...)
  if ok then
    return true
  else
    log.error("Error running %s callback: %s", event, err)
    return false
  end
end

---@param node_type string | string[]
---@return boolean
util.in_node = function(node_type)
  local function in_node(t)
    local has_parser, node = pcall(ts.get_node)
    if not has_parser then
      return false -- silent fail for 1) a older neovim version 2) don't have markdown parser 3) ci tests
    end
    while node do
      if node.type and node:type() == t then
        return true
      end
      node = node.parent and node:parent()
    end
    return false
  end
  if type(node_type) == "string" then
    return in_node(node_type)
  elseif type(node_type) == "table" then
    for _, t in ipairs(node_type) do
      local is_in_node = in_node(t)
      if is_in_node then
        return true
      end
    end
  end
  return false
end

--- from plenary.nvim
util.strdisplaywidth = (function()
  local fallback = function(str, col)
    str = tostring(str)

    ---@diagnostic disable-next-line: unnecessary-if
    if vim.in_fast_event() then
      return #str - (col or 0)
    end

    return vim.fn.strdisplaywidth(str, col)
  end

  if jit and vim.fn.has "win32" ~= 1 then
    local ffi = require "ffi"

    ffi.cdef [[


      typedef unsigned char char_u;


      int linetabsize_col(int startcol, char_u *s);


    ]]

    local ffi_func = function(str, col)
      str = tostring(str)

      local startcol = col or 0

      local s = ffi.new("char[?]", #str + 1)

      ffi.copy(s, str)

      return ffi.C.linetabsize_col(startcol, s) - startcol
    end

    local ok = pcall(ffi_func, "hello")

    if ok then
      return ffi_func
    else
      return fallback
    end
  else
    return fallback
  end
end)()

return util
