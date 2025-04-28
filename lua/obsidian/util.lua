local compat = require "obsidian.compat"
local string, table = string, table
local ts = vim.treesitter
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

<<<<<<< HEAD
------------------------------------
-- Miscellaneous helper functions --
------------------------------------
=======
--- Get the tag under the cursor, if there is one.
---
---@param line string|?
---@param col integer|?
---
---@return string|?
util.cursor_tag = function(line, col)
  local search = require "obsidian.search"

  local current_line = line and line or vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  cur_col = col or cur_col + 1 -- nvim_win_get_cursor returns 0-indexed column

  for match in iter(search.find_tags(current_line)) do
    local open, close, _ = unpack(match)
    if open <= cur_col and cur_col <= close then
      return string.sub(current_line, open + 1, close)
    end
  end

  return nil
end

--- Get the heading under the cursor, if there is one.
---
---@param line string|?
---
---@return string|?
util.cursor_heading = function(line)
  local current_line = line and line or vim.api.nvim_get_current_line()
  return current_line:match "^(%s*)(#+)%s*(.*)$"
end

util.gf_passthrough = function()
  local legacy = require("obsidian").get_client().opts.legacy_commands
  if util.cursor_on_markdown_link(nil, nil, true) then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  else
    return "gf"
  end
end

util.smart_action = function()
  local legacy = require("obsidian").get_client().opts.legacy_commands
  -- follow link if possible
  if util.cursor_on_markdown_link(nil, nil, true) then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  end

  -- show notes with tag if possible
  if util.cursor_tag(nil, nil) then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  end

  if util.cursor_heading() then
    return "<Plug>(ObsidianCycle)"
  end

  -- toggle task if possible
  -- cycles through your custom UI checkboxes, default: [ ] [~] [>] [x]
  return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
end

---Get the path to where a plugin is installed.
---@param name string|?
---@return string|?
util.get_src_root = function(name)
  name = name and name or "obsidian.nvim"
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.endswith(path, name) then
      return path
    end
  end
  return nil
end

--- Get info about a plugin.
---
---@param name string|?
---
---@return { commit: string|?, path: string }|?
util.get_plugin_info = function(name)
  name = name and name or "obsidian.nvim"

  local src_root = util.get_src_root(name)
  if src_root == nil then
    return nil
  end

  local out = { path = src_root }

  local Job = require "plenary.job"
  local output, exit_code = Job:new({ ---@diagnostic disable-line: missing-fields
    command = "git",
    args = { "rev-parse", "HEAD" },
    cwd = src_root,
    enable_recording = true,
  }):sync(1000)

  if exit_code == 0 then
    out.commit = output[1]
  end

  return out
end

---@param cmd string
---@return string|?
util.get_external_dependency_info = function(cmd)
  local Job = require "plenary.job"
  local output, exit_code = Job:new({ ---@diagnostic disable-line: missing-fields
    command = cmd,
    args = { "--version" },
    enable_recording = true,
  }):sync(1000)

  if exit_code == 0 then
    return output[1]
  end
end

---Get an iterator of (bufnr, bufname) over all named buffers. The buffer names will be absolute paths.
---
---@return function () -> (integer, string)|?
util.get_named_buffers = function()
  local idx = 0
  local buffers = vim.api.nvim_list_bufs()

  ---@return integer|?
  ---@return string|?
  return function()
    while idx < #buffers do
      idx = idx + 1
      local bufnr = buffers[idx]
      if vim.api.nvim_buf_is_loaded(bufnr) then
        return bufnr, vim.api.nvim_buf_get_name(bufnr)
      end
    end
  end
end

---Insert text at current cursor position.
---@param text string
util.insert_text = function(text)
  local curpos = vim.fn.getcurpos()
  local line_num, line_col = curpos[2], curpos[3]
  local indent = string.rep(" ", line_col)

  -- Convert text to lines table so we can handle multi-line strings.
  local lines = {}
  for line in text:gmatch "[^\r\n]+" do
    lines[#lines + 1] = line
  end

  for line_index, line in pairs(lines) do
    local current_line_num = line_num + line_index - 1
    local current_line = vim.fn.getline(current_line_num)
    assert(type(current_line) == "string")

    -- Since there's no column 0, remove extra space when current line is blank.
    if current_line == "" then
      indent = indent:sub(1, -2)
    end

    local pre_txt = current_line:sub(1, line_col)
    local post_txt = current_line:sub(line_col + 1, -1)
    local inserted_txt = pre_txt .. line .. post_txt

    vim.fn.setline(current_line_num, inserted_txt)

    -- Create new line so inserted_txt doesn't replace next lines
    if line_index ~= #lines then
      vim.fn.append(current_line_num, indent)
    end
  end
end

---@param bufnr integer
---@return string
util.buf_get_full_text = function(bufnr)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n")
  if vim.api.nvim_get_option_value("eol", { buf = bufnr }) then
    text = text .. "\n"
  end
  return text
end

--- Get the current visual selection of text and exit visual mode.
---
---@param opts { strict: boolean|? }|?
---
---@return { lines: string[], selection: string, csrow: integer, cscol: integer, cerow: integer, cecol: integer }|?
util.get_visual_selection = function(opts)
  opts = opts or {}
  -- Adapted from fzf-lua:
  -- https://github.com/ibhagwan/fzf-lua/blob/6ee73fdf2a79bbd74ec56d980262e29993b46f2b/lua/fzf-lua/utils.lua#L434-L466
  -- this will exit visual mode
  -- use 'gv' to reselect the text
  local _, csrow, cscol, cerow, cecol
  local mode = vim.fn.mode()
  if opts.strict and not vim.endswith(string.lower(mode), "v") then
    return
  end

  if mode == "v" or mode == "V" or mode == "" then
    -- if we are in visual mode use the live position
    _, csrow, cscol, _ = unpack(vim.fn.getpos ".")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "v")
    if mode == "V" then
      -- visual line doesn't provide columns
      cscol, cecol = 0, 999
    end
    -- exit visual mode
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
  else
    -- otherwise, use the last known visual position
    _, csrow, cscol, _ = unpack(vim.fn.getpos "'<")
    _, cerow, cecol, _ = unpack(vim.fn.getpos "'>")
  end

  -- Swap vars if needed
  if cerow < csrow then
    csrow, cerow = cerow, csrow
    cscol, cecol = cecol, cscol
  elseif cerow == csrow and cecol < cscol then
    cscol, cecol = cecol, cscol
  end

  local lines = vim.fn.getline(csrow, cerow)
  assert(type(lines) == "table")
  if vim.tbl_isempty(lines) then
    return
  end

  -- When the whole line is selected via visual line mode ("V"), cscol / cecol will be equal to "v:maxcol"
  -- for some odd reason. So change that to what they should be here. See ':h getpos' for more info.
  local maxcol = vim.api.nvim_get_vvar "maxcol"
  if cscol == maxcol then
    cscol = string.len(lines[1])
  end
  if cecol == maxcol then
    cecol = string.len(lines[#lines])
  end

  ---@type string
  local selection
  local n = #lines
  if n <= 0 then
    selection = ""
  elseif n == 1 then
    selection = string.sub(lines[1], cscol, cecol)
  elseif n == 2 then
    selection = string.sub(lines[1], cscol) .. "\n" .. string.sub(lines[n], 1, cecol)
  else
    selection = string.sub(lines[1], cscol)
      .. "\n"
      .. table.concat(lines, "\n", 2, n - 1)
      .. "\n"
      .. string.sub(lines[n], 1, cecol)
  end

  return {
    lines = lines,
    selection = selection,
    csrow = csrow,
    cscol = cscol,
    cerow = cerow,
    cecol = cecol,
  }
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

--- Check if a string is NaN
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

--- Adapted from `nvim-orgmode/orgmode`
--- Cycle all headings in file between "Show All", "Contents" and "Overview"
---
util.cycle_global = function()
  local mode = vim.g.obsidian_global_cycle_mode or "Show All"
  if not vim.wo.foldenable or mode == "Show All" then
    mode = "Overview"
    vim.cmd [[silent! norm! zMzX]]
  elseif mode == "Contents" then
    mode = "Show All"
    vim.cmd [[silent! norm! zR]]
  elseif mode == "Overview" then
    mode = "Contents"
    vim.wo.foldlevel = 1
    vim.cmd [[silent! norm! zx]]
  end
  vim.api.nvim_echo({ { "Obsidian: " .. mode } }, false, {})
  vim.g.obsidian_global_cycle_mode = mode
end

---@param bufnr integer
---@param cursor integer[]
---@return TSNode?
local function closest_section_node(bufnr, cursor)
  local parser = ts.get_parser(bufnr, "markdown", {})
  assert(parser)
  local cursor_range = { cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] + 1 }
  local node = parser:named_node_for_range(cursor_range)

  if not node then
    return nil
  end

  if node:type() == "section" then
    return node
  end

  while node and node:type() ~= "section" do
    node = node:parent()
  end

  return node
end

---@param node TSNode
---@return boolean
local function has_child_headlines(node)
  return vim.iter(node:iter_children()):any(function(child)
    return child:type() == "atx_heading"
  end)
end

---@param node TSNode
---@return TSNode[]?
local function get_child_headlines(node)
  local ret = {}
  for child in node:iter_children() do
    if child:type() == "section" then
      ret[#ret + 1] = child
    end
  end
  return ret
end

---@return boolean
local function is_one_line(node)
  local start_row, _, end_row, end_col = node:parent():range()
  -- One line sections have end range on the next line with 0 column
  -- Example: If headline is on line 5, range will be (5, 1, 6, 0)
  return start_row == end_row or (start_row + 1 == end_row and end_col == 0)
end

---@param node TSNode
---@return boolean
local function can_section_expand(node)
  return not is_one_line(node) or has_child_headlines(node)
end

--- Cycle heading state under cursor
util.cycle = function()
  local current_buffer = vim.api.nvim_get_current_buf()
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local current_line = vim.fn.line "."

  -- Ensure fold system is active
  if not vim.wo.foldenable then
    vim.wo.foldenable = true
    vim.cmd [[silent! norm! zx]] -- Refresh folds
  end

  -- Check current fold state
  local current_fold_level = vim.fn.foldlevel(current_line)
  if current_fold_level == 0 then
    return
  end

  -- Handle closed folds first
  local is_fold_closed = vim.fn.foldclosed(current_line) ~= -1
  if is_fold_closed then
    return vim.cmd [[silent! norm! zo]] -- Open closed fold
  end

  -- Find Markdown section structure
  local current_section_node = closest_section_node(current_buffer, cursor_position)
  if not current_section_node then
    return
  end

  -- Ignore non-expandable sections
  if not can_section_expand(current_section_node) then
    return
  end

  -- Fold state management
  local child_sections = get_child_headlines(current_section_node)
  local should_close_parent = #child_sections == 0

  if not should_close_parent then
    local has_nested_structure = false

    -- Process child fold states
    for _, child_node in ipairs(child_sections or {}) do
      if can_section_expand(child_node) then
        has_nested_structure = true
        local child_start_line = child_node:start() + 1

        -- Close open child folds first
        if vim.fn.foldclosed(child_start_line) == -1 then
          vim.cmd(string.format("silent! keepjumps norm! %dggzc", child_start_line))
          should_close_parent = true
        end
      end
    end

    -- Return to original cursor position
    vim.cmd(string.format("silent! keepjumps norm! %dgg", current_line))

    -- Close parent if no actual nesting exists
    if not should_close_parent and not has_nested_structure then
      should_close_parent = true
    end
  end

  -- Execute final fold action
  if should_close_parent then
    vim.cmd [[silent! norm! zc]] -- Close parent fold
  else
    vim.cmd [[silent! norm! zczO]] -- Force fold refresh
  end
end

return util
