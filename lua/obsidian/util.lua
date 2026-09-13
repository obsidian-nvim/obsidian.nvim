local string, table = string, table
local util = {}

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

------------------------------------
-- Miscellaneous helper functions --
------------------------------------

--- Check whether a filename stem is valid across supported platforms.
---@param name string
---@return boolean valid
---@return string? reason
util.is_valid_filename = function(name)
  if vim.g.obsidian_allow_invalid_names then
    return true, nil
  end
  if not name or name == "" then
    return false, "cannot be empty"
  end

  local forbidden = name:match '[<>:"/\\|?*%z]'
  if forbidden then
    return false, ("contains forbidden character: %q"):format(forbidden)
  elseif name:match "[\1-\31]" then
    return false, "contains a control character"
  elseif name:match "[%. ]$" then
    return false, "cannot end with a space or period"
  end
  return true, nil
end

--- Check if a string contains invalid characters.
---
--- @param fname string|obsidian.Path
---
--- @return boolean
util.contains_invalid_characters = function(fname)
  fname = tostring(fname)
  local invalid_chars = "#^%[%]|"
  return string.find(fname, "[" .. invalid_chars .. "]") ~= nil
end

---@param event string
---@param callback fun(...)|?
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

--- HACK: because LazyVim and some users by default sets vim.deprecate to no-op
--- Shows a deprecation message to the user.
---
---@param name        string     Deprecated feature (function, API, etc.).
---@param alternative string|nil Suggested alternative feature.
---@param version     string     Version when the deprecated function will be removed.
---
util.deprecate = function(name, alternative, version)
  vim.validate("name", name, "string")
  vim.validate("alternative", alternative, "string", true)
  vim.validate("version", version, "string", true)

  local msg = ("%s is deprecated"):format(name)
  msg = alternative and ("%s, use %s instead."):format(msg, alternative) or (msg .. ".")
  msg = ("%s\nFeature will be removed in %s %s"):format(msg, "obsidian.nvim", version)
  vim.notify_once(msg, vim.log.levels.WARN)
end

------------------------------------------------
--- back compatibility stuff, remove in 4.0 ----
------------------------------------------------

util.urlencode = require("obsidian.uri").encode
util.format_date = require("obsidian.date").format

return util
