local frontmatter = require "obsidian.completion.frontmatter"

local M = {}

local TagCharsOptional = "[%w\128-\244_/-]*"

---@type { pattern: string, offset: integer }[]
local TAG_PATTERNS = {
  { pattern = "[%s%(]#" .. TagCharsOptional .. "$", offset = 2 },
  { pattern = "^#" .. TagCharsOptional .. "$", offset = 1 },
}

---@param input string
---@return string?
M.find_tags_start = function(input)
  for _, pattern in ipairs(TAG_PATTERNS) do
    local match = string.match(input, pattern.pattern)
    if match then
      return string.sub(match, pattern.offset + 1)
    end
  end
end

---@param request obsidian.completion.Request
---@return boolean, string?
M.can_complete = function(request)
  -- Frontmatter tags are ordinary property values and are handled by the
  -- frontmatter completion source.
  if request.bufnr and request.line and frontmatter.is_in_frontmatter(request.bufnr, request.line) then
    return false
  end

  local search = M.find_tags_start(request.cursor_before_line)
  if not search or string.len(search) == 0 then
    return false
  end

  return true, search
end

return M
