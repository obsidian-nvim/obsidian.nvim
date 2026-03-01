local Note = require "obsidian.note"
local parse_tags = require("obsidian.parse.tags").parse_tags

local M = {}

---@param input string
---@return string|?
M.find_tags_start = function(input)
  local tags = parse_tags(input)
  if #tags == 0 then
    return
  end

  -- Check if the last tag extends to the end of the input (i.e. cursor is on a tag).
  local last_tag = tags[#tags]
  return last_tag[3]
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

---@return boolean, string|?, boolean|?
M.can_complete = function(request)
  local search = M.find_tags_start(request.context.cursor_before_line)
  if not search or string.len(search) == 0 then
    return false
  end

  -- Check if we're inside frontmatter.
  local in_frontmatter = false
  local line = request.context.cursor.line
  local frontmatter_start, frontmatter_end = get_frontmatter_boundaries(request.context.bufnr)
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

M.get_trigger_characters = function()
  return { "#" }
end

M.get_keyword_pattern = function()
  -- Note that this is a vim pattern, not a Lua pattern. See ':help pattern'.
  -- The enclosing [=[ ... ]=] is just a way to mark the boundary of a
  -- string in Lua.
  -- return [=[\%(^\|[^#]\)\zs#[a-zA-Z0-9_/-]\+]=]
  return "#[a-zA-Z0-9_/\\x80-\\xff-]\\+"
end

return M
