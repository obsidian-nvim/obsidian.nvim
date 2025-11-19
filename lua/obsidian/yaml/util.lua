local util = require "obsidian.util"

return {
---Strip YAML comments from a string.
---@param str string
---@return string
strip_comments = function(str)
  if vim.startswith(str, "# ") then
    return ""
  elseif not util.has_enclosing_chars(str) then
    return select(1, string.gsub(str, [[%s+#%s.*$]], ""))
  else
    return str
  end
end

}
