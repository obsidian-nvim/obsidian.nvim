local util = require "obsidian.util"

local STRING_ENCLOSING_CHARS = { [["]], [[']] }
local M = {}

---Get the substring of `str` starting from the first character and up to the stop character,
---ignoring any enclosing characters (like double quotes) and stop characters that are within the
---enclosing characters. For example, if `str = [=["foo", "bar"]=]` and `stop_char = ","`, this
---would return the string `[=[foo]=]`.
---
---@param str string
---@param stop_chars string[]
---@param keep_stop_char boolean|?
---@return string|?, string
M.next_item = function(str, stop_chars, keep_stop_char)
  local og_str = str

  -- Check for enclosing characters.
  local enclosing_char = nil
  local first_char = string.sub(str, 1, 1)
  for _, c in ipairs(STRING_ENCLOSING_CHARS) do
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

---Strip YAML comments from a string.
---@param str string
---@return string
M.strip_comments = function(str)
  if vim.startswith(str, "# ") then
    return ""
  elseif not util.has_enclosing_chars(str) then
    return select(1, string.gsub(str, [[%s+#%s.*$]], ""))
  else
    return str
  end
end

return M
