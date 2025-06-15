local compat = require "obsidian.compat"
local string, table = string, table
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
--- Iter tools ----
-------------------

---Create an enumeration iterator over an iterable.
---@param iterable table|string|function
---@return function
util.enumerate = function(iterable)
  local iterator = vim.iter(iterable)
  local i = 0

  return function()
    local next = iterator()
    if next == nil then
      return nil, nil
    else
      i = i + 1
      return i, next
    end
  end
end

---Zip two iterables together.
---@param iterable1 table|string|function
---@param iterable2 table|string|function
---@return function
util.zip = function(iterable1, iterable2)
  local iterator1 = vim.iter(iterable1)
  local iterator2 = vim.iter(iterable2)

  return function()
    local next1 = iterator1()
    local next2 = iterator2()
    if next1 == nil or next2 == nil then
      return nil
    else
      return next1, next2
    end
  end
end

-------------------
--- Table tools ---
-------------------

---Check if a table contains a key.
---
---@param t table
---@param needle any
---@return boolean
util.tbl_contains_key = function(t, needle)
  return vim.list_contains(vim.tbl_keys(t), needle)
end

---Check if an object is an array-like table.
---@param t any
---@return boolean
util.tbl_is_array = function(t)
  if type(t) ~= "table" then
    return false
  end

  return compat.is_list(t)
end

---Check if an object is an non-array table.
---@param t any
---@return boolean
util.tbl_is_mapping = function(t)
  return type(t) == "table" and (vim.tbl_isempty(t) or not util.tbl_is_array(t))
end

---Return a new list table with only the unique values of the original table.
---
---@param t table
---@return any[]
util.tbl_unique = function(t)
  local out = {}
  for _, val in pairs(t) do
    if not vim.list_contains(out, val) then
      out[#out + 1] = val
    end
  end
  return out
end

--- Clear all values from a table.
---
---@param t table
util.tbl_clear = function(t)
  for k, _ in pairs(t) do
    t[k] = nil
  end
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

local hex_to_char = function(hex)
  return string.char(tonumber(hex, 16))
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

--- Decode a URL-encoded string.
---
---@param str string
---
---@return string
util.urldecode = function(str)
  str = str:gsub("%%(%x%x)", hex_to_char)
  return str
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
  if string.match(s, "^%s*[-+*]%s+%[.%]") ~= nil then
    return true
  end
  -- 1. [ ] and 1) [ ]
  if string.match(s, "^%s*%d+[%.%)]%s+%[.%]") ~= nil then
    return true
  end
  return false
end

---Check if a string is a valid URL.
---@param s string
---@return boolean
util.is_url = function(s)
  local search = require "obsidian.search"

  if
    string.match(vim.trim(s), "^" .. search.Patterns[search.RefTypes.NakedUrl] .. "$")
    or string.match(vim.trim(s), "^" .. search.Patterns[search.RefTypes.FileUrl] .. "$")
    or string.match(vim.trim(s), "^" .. search.Patterns[search.RefTypes.MailtoUrl] .. "$")
  then
    return true
  else
    return false
  end
end

---Checks if a given string represents an image file based on its suffix.
---
---@param s string: The input string to check.
---@return boolean: Returns true if the string ends with a supported image suffix, false otherwise.
util.is_img = function(s)
  for _, suffix in ipairs { ".png", ".jpg", ".jpeg", ".heic", ".gif", ".svg", ".ico" } do
    if vim.endswith(s, suffix) then
      return true
    end
  end
  return false
end

-- This function removes a single backslash within double square brackets
util.unescape_single_backslash = function(text)
  return text:gsub("(%[%[[^\\]+)\\(%|[^\\]+]])", "%1%2")
end

util.string_enclosing_chars = { [["]], [[']] }

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

---Get the substring of `str` starting from the first character and up to the stop character,
---ignoring any enclosing characters (like double quotes) and stop characters that are within the
---enclosing characters. For example, if `str = [=["foo", "bar"]=]` and `stop_char = ","`, this
---would return the string `[=[foo]=]`.
---
---@param str string
---@param stop_chars string[]
---@param keep_stop_char boolean|?
---@return string|?, string
util.next_item = function(str, stop_chars, keep_stop_char)
  local og_str = str

  -- Check for enclosing characters.
  local enclosing_char = nil
  local first_char = string.sub(str, 1, 1)
  for _, c in ipairs(util.string_enclosing_chars) do
    if first_char == c then
      enclosing_char = c
      str = string.sub(str, 2)
      break
    end
  end

  local result
  local hits

  for _, stop_char in ipairs(stop_chars) do
    -- First check for next item when `stop_char` is present.
    if enclosing_char ~= nil then
      result, hits = string.gsub(
        str,
        "([^" .. enclosing_char .. "]+)([^\\]?)" .. enclosing_char .. "%s*" .. stop_char .. ".*",
        "%1%2"
      )
      result = enclosing_char .. result .. enclosing_char
    else
      result, hits = string.gsub(str, "([^" .. stop_char .. "]+)" .. stop_char .. ".*", "%1")
    end
    if hits ~= 0 then
      local i = string.find(str, stop_char, string.len(result), true)
      if keep_stop_char then
        return result .. stop_char, string.sub(str, i + 1)
      else
        return result, string.sub(str, i + 1)
      end
    end

    -- Now check for next item without the `stop_char` after.
    if not keep_stop_char and enclosing_char ~= nil then
      result, hits = string.gsub(str, "([^" .. enclosing_char .. "]+)([^\\]?)" .. enclosing_char .. "%s*$", "%1%2")
      result = enclosing_char .. result .. enclosing_char
    elseif not keep_stop_char then
      result = str
      hits = 1
    else
      result = nil
      hits = 0
    end
    if hits ~= 0 then
      if keep_stop_char then
        result = result .. stop_char
      end
      return result, ""
    end
  end

  return nil, og_str
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

---Strip enclosing characters like quotes from a string.
---@param str string
---@return string
util.strip_enclosing_chars = function(str)
  local c_start = string.sub(str, 1, 1)
  local c_end = string.sub(str, #str, #str)
  for _, enclosing_char in ipairs(util.string_enclosing_chars) do
    if c_start == enclosing_char and c_end == enclosing_char then
      str = string.sub(str, 2, #str - 1)
      break
    end
  end
  return str
end

---Check if a string has enclosing characters like quotes.
---@param str string
---@return boolean
util.has_enclosing_chars = function(str)
  for _, enclosing_char in ipairs(util.string_enclosing_chars) do
    if vim.startswith(str, enclosing_char) and vim.endswith(str, enclosing_char) then
      return true
    end
  end
  return false
end

---Strip YAML comments from a string.
---@param str string
---@return string
util.strip_comments = function(str)
  if vim.startswith(str, "# ") then
    return ""
  elseif not util.has_enclosing_chars(str) then
    return select(1, string.gsub(str, [[%s+#%s.*$]], ""))
  else
    return str
  end
end

---Check if a string contains a substring.
---@param str string
---@param substr string
---@return boolean
util.string_contains = function(str, substr)
  local i = string.find(str, substr, 1, true)
  return i ~= nil
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

---@param link string
---@param opts { include_naked_urls: boolean|?, include_file_urls: boolean|?, include_block_ids: boolean|?, link_type: obsidian.search.RefTypes|? }|?
---
---@return string|?, string|?, obsidian.search.RefTypes|?
util.parse_link = function(link, opts)
  local search = require "obsidian.search"

  opts = opts and opts or {}

  local link_type = opts.link_type
  if link_type == nil then
    for match in
      vim.iter(search.find_refs(link, {
        include_naked_urls = opts.include_naked_urls,
        include_file_urls = opts.include_file_urls,
        include_block_ids = opts.include_block_ids,
      }))
    do
      local _, _, m_type = unpack(match)
      if m_type then
        link_type = m_type
        break
      end
    end
  end

  if link_type == nil then
    return nil
  end

  local link_location, link_name
  if link_type == search.RefTypes.Markdown then
    link_location = link:gsub("^%[(.-)%]%((.*)%)$", "%2")
    link_name = link:gsub("^%[(.-)%]%((.*)%)$", "%1")
  elseif link_type == search.RefTypes.NakedUrl then
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.FileUrl then
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.WikiWithAlias then
    link = util.unescape_single_backslash(link)
    -- remove boundary brackets, e.g. '[[XXX|YYY]]' -> 'XXX|YYY'
    link = link:sub(3, #link - 2)
    -- split on the "|"
    local split_idx = link:find "|"
    link_location = link:sub(1, split_idx - 1)
    link_name = link:sub(split_idx + 1)
  elseif link_type == search.RefTypes.Wiki then
    -- remove boundary brackets, e.g. '[[YYY]]' -> 'YYY'
    link = link:sub(3, #link - 2)
    link_location = link
    link_name = link
  elseif link_type == search.RefTypes.BlockID then
    link_location = util.standardize_block(link)
    link_name = link
  else
    error("not implemented for " .. link_type)
  end

  return link_location, link_name, link_type
end

------------------------------------
-- Miscellaneous helper functions --
------------------------------------
---@enum OSType
util.OSType = {
  Linux = "Linux",
  Wsl = "Wsl",
  Windows = "Windows",
  Darwin = "Darwin",
  FreeBSD = "FreeBSD",
}

util._current_os = nil

---Get the running operating system.
---Reference https://vi.stackexchange.com/a/2577/33116
---@return OSType
util.get_os = function()
  if util._current_os ~= nil then
    return util._current_os
  end

  local this_os
  if vim.fn.has "win32" == 1 then
    this_os = util.OSType.Windows
  else
    local sysname = vim.loop.os_uname().sysname
    local release = vim.loop.os_uname().release:lower()
    if sysname:lower() == "linux" and string.find(release, "microsoft") then
      this_os = util.OSType.Wsl
    else
      this_os = sysname
    end
  end

  assert(this_os)
  util._current_os = this_os
  return this_os
end

--- Get a nice icon for a file or URL, if possible.
---
---@param path string
---
---@return string|?, string|? (icon, hl_group) The icon and highlight group.
util.get_icon = function(path)
  if util.is_url(path) then
    local icon = ""
    local _, hl_group = util.get_icon "blah.html"
    return icon, hl_group
  else
    local ok, res = pcall(function()
      local icon, hl_group = require("nvim-web-devicons").get_icon(path, nil, { default = true })
      return { icon, hl_group }
    end)
    if ok and type(res) == "table" then
      local icon, hlgroup = unpack(res)
      return icon, hlgroup
    elseif vim.endswith(path, ".md") then
      return ""
    end
  end
  return nil
end

---@param anchor obsidian.note.HeaderAnchor
---@return string
util.format_anchor_label = function(anchor)
  return string.format(" ❯ %s", anchor.header)
end

-- We are very loose here because obsidian allows pretty much anything
util.ANCHOR_LINK_PATTERN = "#[%w%d\128-\255][^#]*"

util.BLOCK_PATTERN = "%^[%w%d][%w%d-]*"

util.BLOCK_LINK_PATTERN = "#" .. util.BLOCK_PATTERN

--- Strip anchor links from a line.
---@param line string
---@return string, string|?
util.strip_anchor_links = function(line)
  ---@type string|?
  local anchor

  while true do
    local anchor_match = string.match(line, util.ANCHOR_LINK_PATTERN .. "$")
    if anchor_match then
      anchor = anchor or ""
      anchor = anchor_match .. anchor
      line = string.sub(line, 1, -anchor_match:len() - 1)
    else
      break
    end
  end

  return line, anchor and util.standardize_anchor(anchor)
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

---Check if a string is NaN
---
---@param v any
---@return boolean
util.isNan = function(v)
  return tostring(v) == tostring(0 / 0)
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
      buffer = lines[#lines] -- Store remaining partial line
    end
  end
end

return util
