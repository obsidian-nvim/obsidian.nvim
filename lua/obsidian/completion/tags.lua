local Note = require "obsidian.note"
local Patterns = require("obsidian.search").Patterns

local M = {}

-- TODO: use proper unicode match

---@type { pattern: string, offset: integer }[]
local TAG_PATTERNS = {
  { pattern = "[%s%(]#" .. Patterns.TagCharsOptional .. "$", offset = 2 },
  { pattern = "^#" .. Patterns.TagCharsOptional .. "$", offset = 1 },
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

--- Find the boundaries of the YAML frontmatter within the buffer.
---@param bufnr integer
---@return integer|?, integer|?
local get_frontmatter_boundaries = function(bufnr)
  local note = Note.from_buffer(bufnr)
  if note.frontmatter_end_line ~= nil then
    return 1, note.frontmatter_end_line
  end
end

---@param request obsidian.completion.Request
---@return boolean, string|?, boolean|?
M.can_complete = function(request)
  local search = M.find_tags_start(request.cursor_before_line)
  if not search or string.len(search) == 0 then
    return false
  end

  -- Check if we're inside frontmatter.
  local in_frontmatter = false
  local line = request.line + 1 -- 1-indexed
  local frontmatter_start, frontmatter_end = get_frontmatter_boundaries(request.bufnr)
  if
    frontmatter_start ~= nil
    and frontmatter_start <= (line + 1)
    and frontmatter_end ~= nil
    and line <= frontmatter_end
  then
    in_frontmatter = true
  end

  return true, search, in_frontmatter
end

return M
