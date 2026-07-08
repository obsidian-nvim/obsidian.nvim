---@param word string
---@return boolean
local function is_suggestion(word)
  return word == "test"
end

---@param char string
---@return boolean
local function is_word_char(char)
  return char:match "[%w_]" ~= nil
end

---@param line string
---@param start_idx integer 1-indexed byte offset
---@param end_idx integer 1-indexed byte offset
---@param is_boundary_char fun(char: string): boolean
---@return boolean
local function is_match(line, start_idx, end_idx, is_boundary_char)
  local before = start_idx > 1 and line:sub(start_idx - 1, start_idx - 1) or ""
  local after = end_idx < #line and line:sub(end_idx + 1, end_idx + 1) or ""
  return not is_boundary_char(before) and not is_boundary_char(after)
end

---@param line string
---@param start_idx integer 1-indexed byte offset
---@param end_idx integer 1-indexed byte offset
---@return boolean
local function is_word_match(line, start_idx, end_idx)
  return is_match(line, start_idx, end_idx, is_word_char)
end

---@param line string
---@param start_idx integer 1-indexed byte offset
---@param end_idx integer 1-indexed byte offset
---@return boolean
local function is_in_wiki_link(line, start_idx, end_idx)
  local before_word = line:sub(1, start_idx - 1)
  local open_start = before_word:match "^.*()%[%["
  if not open_start then
    return false
  end

  local close_start = before_word:match "^.*()%]%]"
  if close_start and close_start > open_start then
    return false
  end

  return line:find("]]", end_idx + 1, true) ~= nil
end

---@param hints lsp.InlayHint[]
---@param line string
---@param line_nr integer
return function(hints, line, line_nr)
  local search_start = 1

  while true do
    local start_idx, end_idx = line:find("test", search_start, true)
    if not start_idx or not end_idx then
      break
    end

    if
      is_word_match(line, start_idx, end_idx)
      and not is_in_wiki_link(line, start_idx, end_idx)
      and is_suggestion(line:sub(start_idx, end_idx))
    then
      local start_col = start_idx - 1
      local end_col = end_idx

      hints[#hints + 1] = {
        position = { line = line_nr, character = start_col },
        label = "[[",
        paddingLeft = false,
        paddingRight = false,
      }
      hints[#hints + 1] = {
        position = { line = line_nr, character = end_col },
        label = "]]",
        paddingLeft = false,
        paddingRight = false,
      }
    end

    search_start = end_idx + 1
  end
end
