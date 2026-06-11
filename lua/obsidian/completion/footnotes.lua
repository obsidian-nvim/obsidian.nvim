local M = {}

---Check if a footnote completion request can/should be carried out. Returns a
---boolean and, if true, the search term and the column indices of where the
---completion items should be inserted.
---
---@param request obsidian.completion.Request
---@return boolean can_complete
---@return string|? term
---@return integer|? insert_start 0-indexed
---@return integer|? insert_end 0-indexed, exclusive
M.can_complete = function(request)
  local before = request.cursor_before_line

  -- An unclosed "[^..." immediately before the cursor.
  local m_start = before:find "%[%^[^%]%[%s]*$"
  if not m_start then
    return false
  end

  -- "[[^..." is a wiki-style block link, not a footnote.
  if m_start > 1 and before:sub(m_start - 1, m_start - 1) == "[" then
    return false
  end

  local term = before:sub(m_start + 2)

  -- If the cursor is right before a closing bracket, replace it as well.
  local insert_end = request.character
  if request.cursor_after_line:sub(1, 1) == "]" then
    insert_end = insert_end + 1
  end

  return true, term, m_start - 1, insert_end
end

return M
