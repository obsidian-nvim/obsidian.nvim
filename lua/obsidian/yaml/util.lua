local STRING_ENCLOSING_CHARS = { [["]], [[']] }
local M = {}

---Get the substring of `str` starting from the first character and up to the stop character,
---ignoring any enclosing characters (like double quotes) and stop characters that are within the
---enclosing characters. For example, if `str = [=["foo", "bar"]=]` and `stop_char = ","`, this
---would return the source substring `[=["foo"]=]`, including its quotes.
---
---@param str string
---@param stop_chars string[]
---@param keep_stop_char boolean|?
---@return string|?, string
M.next_item = function(str, stop_chars, keep_stop_char)
  -- Return literal substrings: rebuilding quoted items loses source offsets.
  local quote
  local depth = 0 ---@type number
  local i = 1
  while i <= #str do
    local c = str:sub(i, i)
    if quote then
      if quote == '"' and c == "\\" then
        i = i + 1
      elseif c == quote then
        if quote == "'" and str:sub(i + 1, i + 1) == "'" then
          i = i + 1
        else
          quote = nil
        end
      end
    elseif (c == '"' or c == "'") and (i == 1 or str:sub(i - 1, i - 1):match "[%s%[%{,:]") then
      quote = c
    else
      if c == "]" or c == "}" then
        depth = depth - 1
      end
      if depth == 0 and vim.list_contains(stop_chars, c) then
        return str:sub(1, keep_stop_char and i or i - 1), str:sub(i + 1)
      end
      if c == "[" or c == "{" then
        depth = depth + 1
      end
    end
    i = i + 1
  end
  if not keep_stop_char and not quote and depth == 0 then
    return str, ""
  end
  return nil, str
end

---Strip enclosing characters like quotes from a string.
---@param str string
---@return string
M.strip_enclosing_chars = function(str)
  local c_start = string.sub(str, 1, 1)
  local c_end = string.sub(str, #str, #str)
  for _, enclosing_char in ipairs(STRING_ENCLOSING_CHARS) do
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
M.has_enclosing_chars = function(str)
  for _, enclosing_char in ipairs(STRING_ENCLOSING_CHARS) do
    if vim.startswith(str, enclosing_char) and vim.endswith(str, enclosing_char) then
      return true
    end
  end
  return false
end

---Strip YAML comments from a string.
---@param str string
---@return string
M.strip_comments = function(str)
  local quote
  local i = 1
  while i <= #str do
    local c = str:sub(i, i)
    if quote then
      if quote == '"' and c == "\\" then
        i = i + 1
      elseif c == quote then
        if quote == "'" and str:sub(i + 1, i + 1) == "'" then
          i = i + 1
        else
          quote = nil
        end
      end
    elseif (c == '"' or c == "'") and (i == 1 or str:sub(i - 1, i - 1):match "[%s%[%{,:]") then
      quote = c
    elseif c == "#" and (i == 1 or str:sub(i - 1, i - 1):match "%s") then
      -- Preserve the existing Obsidian extension accepting unquoted #tags.
      if i == #str or str:sub(i + 1, i + 1):match "%s" then
        return (str:sub(1, i - 1):gsub("%s+$", ""))
      end
    end
    i = i + 1
  end
  return str
end

return M
