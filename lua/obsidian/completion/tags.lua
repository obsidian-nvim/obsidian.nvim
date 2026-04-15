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

--- Check if cursor line is a YAML list item under the `tags:` key in frontmatter.
--- Scans backwards from cursor to find the parent key.
---@param bufnr integer
---@param cursor_line integer 1-indexed
---@param cursor_before_line string
---@return boolean is_tags_item
---@return string search_term
local function in_frontmatter_tags_list(bufnr, cursor_line, cursor_before_line)
  -- Check if current line looks like a YAML list item: "  - something" or "  - "
  local item_text = cursor_before_line:match "^%s+-%s+(.*)" or cursor_before_line:match "^%s+-%s*$" and ""
  if item_text == nil then
    return false, ""
  end

  -- Scan backwards to find the parent key
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_line - 1, false)
  for i = #lines, 1, -1 do
    local l = lines[i]
    -- Match a YAML key with no value (start of block sequence), e.g. "tags:"
    local key = l:match "^(%w[%w_-]*):%s*$"
    if key then
      return key == "tags", item_text
    end
    -- If we hit a line that's not a list item or empty, stop
    if not l:match "^%s+%-" and not l:match "^%s*$" then
      break
    end
  end
  return false, ""
end

---@param request obsidian.completion.Request
---@return boolean, string|?, boolean|?
M.can_complete = function(request)
  local line = request.line + 1 -- 1-indexed
  local frontmatter_start, frontmatter_end = get_frontmatter_boundaries(request.bufnr)
  local in_frontmatter = frontmatter_start ~= nil
    and frontmatter_start <= (line + 1)
    and frontmatter_end ~= nil
    and line <= frontmatter_end

  -- In frontmatter, check for tags list item trigger (no # needed)
  if in_frontmatter then
    local is_tags, term = in_frontmatter_tags_list(request.bufnr, line, request.cursor_before_line)
    if is_tags then
      return true, term, true
    end
  end

  -- Standard #tag trigger
  local search = M.find_tags_start(request.cursor_before_line)
  if not search or string.len(search) == 0 then
    return false
  end

  return true, search, in_frontmatter
end

return M
