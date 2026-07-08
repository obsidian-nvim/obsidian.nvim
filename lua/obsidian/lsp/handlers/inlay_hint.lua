local search = require "obsidian.search"

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

---@param char string
---@return boolean
local function is_tag_char(char)
  return char:match "[%w_/-]" ~= nil
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
local function is_tag_match(line, start_idx, end_idx)
  return is_match(line, start_idx, end_idx, is_tag_char)
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

---@param line string
---@param start_idx integer 1-indexed byte offset
---@return boolean
local function is_existing_tag(line, start_idx)
  return start_idx > 1 and line:sub(start_idx - 1, start_idx - 1) == "#"
end

---@param tag_locs obsidian.TagLocation[]
---@return string[]
local function tags_from_locations(tag_locs)
  local tags = {}
  for _, tag_loc in ipairs(tag_locs) do
    tags[tag_loc.tag] = true
  end

  local out = vim.tbl_keys(tags)
  table.sort(out, function(a, b)
    return #a > #b
  end)
  return out
end

---@param hints lsp.InlayHint[]
---@param line string
---@param line_nr integer
---@param tags string[]
local function add_tag_hints(hints, line, line_nr, tags)
  local seen_positions = {}

  for _, tag in ipairs(tags) do
    local search_start = 1

    while true do
      local start_idx, end_idx = line:find(tag, search_start, true)
      if not start_idx or not end_idx then
        break
      end

      local start_col = start_idx - 1
      if
        not seen_positions[start_col]
        and is_tag_match(line, start_idx, end_idx)
        and not is_existing_tag(line, start_idx)
        and not is_in_wiki_link(line, start_idx, end_idx)
      then
        hints[#hints + 1] = {
          position = { line = line_nr, character = start_col },
          label = "#",
          paddingLeft = false,
          paddingRight = false,
        }
        seen_positions[start_col] = true
      end

      search_start = end_idx + 1
    end
  end
end

---@param hints lsp.InlayHint[]
---@param line string
---@param line_nr integer
local function add_link_hints(hints, line, line_nr)
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

---@param bufnr integer
---@param range lsp.Range|?
---@param tags string[]
---@return lsp.InlayHint[]
local function get_hints(bufnr, range, tags)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = range and range.start.line or 0
  local end_line = range and range["end"].line or (line_count - 1)

  start_line = math.max(start_line, 0)
  end_line = math.min(end_line, line_count - 1)

  if end_line < start_line then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

  ---@type lsp.InlayHint[]
  local hints = {}

  for offset, line in ipairs(lines) do
    local line_nr = start_line + offset - 1
    add_link_hints(hints, line, line_nr)
    add_tag_hints(hints, line, line_nr, tags)
  end

  return hints
end

---@param params lsp.InlayHintParams
---@param callback fun(_: any, hints: lsp.InlayHint[])
return function(params, callback)
  local bufnr = params and params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or 0
  local range = params and params.range or nil

  search.find_tags_async("", function(tag_locs)
    callback(nil, get_hints(bufnr, range, tags_from_locations(tag_locs)))
  end)
end
