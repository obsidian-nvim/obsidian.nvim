local M = {}

---@class obsidian.completion.FrontmatterContext
---@field kind "key"|"value"
---@field key string?
---@field term string
---@field insert_start integer 0-indexed byte offset
---@field insert_end integer 0-indexed byte offset, end-exclusive
---@field add_colon boolean?

local function is_boundary(line)
  return line:match "^%-%-%-+%s*$" ~= nil
end

---@param bufnr integer
---@param line integer 0-indexed
---@return boolean
function M.is_in_frontmatter(bufnr, line)
  if line <= 0 then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not is_boundary(lines[1] or "") then
    return false
  end

  for i = 2, #lines do
    if is_boundary(lines[i]) then
      return line < i - 1
    end
  end

  -- Also complete while the closing boundary is still being written.
  return line < #lines
end

---@param value string
---@return string
local function completion_term(value)
  value = vim.trim(value)
  local first = value:sub(1, 1)
  if first == [["]] or first == "'" then
    value = value:sub(2)
  end
  return value
end

---@param full_line string
---@param cursor integer 0-indexed byte offset
---@param start_lua integer 1-indexed byte offset
---@return integer
local function value_end(full_line, cursor, start_lua)
  local comment = full_line:find("%s+#%s", math.max(cursor + 1, start_lua))
  local end_lua = comment and comment - 1 or #full_line
  while end_lua >= start_lua and full_line:sub(end_lua, end_lua):match "%s" do
    end_lua = end_lua - 1
  end
  return math.max(cursor, end_lua)
end

---@param request obsidian.completion.Request
---@return obsidian.completion.FrontmatterContext?
function M.context(request)
  if not M.is_in_frontmatter(request.bufnr, request.line) then
    return nil
  end

  local before = request.cursor_before_line
  local full_line = before .. request.cursor_after_line
  local cursor = request.character

  -- Block sequence item, e.g. "  - dra". Find its top-level property.
  local indent = full_line:match "^([ \t]+)%-"
  local item_prefix = full_line:match "^([ \t]+%-%s*)"
  local block_item_start = item_prefix and #item_prefix + 1 or nil
  if indent and block_item_start and cursor >= block_item_start - 1 then
    local previous = vim.api.nvim_buf_get_lines(request.bufnr, 1, request.line, false)
    local key
    for i = #previous, 1, -1 do
      local line = previous[i]
      if not line:match "^%s*$" then
        local line_indent = #(line:match "^%s*" or "")
        if line_indent < #indent then
          key = line:match "^([^:#][^:]-):%s*$"
          break
        elseif line_indent == 0 then
          break
        end
      end
    end

    if key then
      local start_col = block_item_start - 1
      return {
        kind = "value",
        key = vim.trim(key),
        term = completion_term(before:sub(block_item_start)),
        insert_start = start_col,
        insert_end = value_end(full_line, cursor, block_item_start),
      }
    end
    return nil
  end

  -- Only top-level mappings are Obsidian properties.
  if full_line:match "^%s" then
    return nil
  end

  local colon = full_line:find(":", 1, true)
  if not colon then
    local key_end = #full_line
    while key_end > 0 and full_line:sub(key_end, key_end):match "%s" do
      key_end = key_end - 1
    end
    return {
      kind = "key",
      term = vim.trim(before),
      insert_start = 0,
      insert_end = math.max(cursor, key_end),
      add_colon = true,
    }
  end

  local key = vim.trim(full_line:sub(1, colon - 1))
  if key == "" or key:sub(1, 1) == "#" then
    return nil
  end

  local colon_col = colon - 1
  if cursor <= colon_col then
    local key_end = colon - 1
    while key_end > 0 and full_line:sub(key_end, key_end):match "%s" do
      key_end = key_end - 1
    end
    return {
      kind = "key",
      term = vim.trim(before),
      insert_start = 0,
      insert_end = key_end,
      add_colon = false,
    }
  end

  local value_start = colon + 1
  while value_start <= #full_line and full_line:sub(value_start, value_start):match "%s" do
    value_start = value_start + 1
  end

  -- Complete one element of an inline sequence, e.g. "tags: [foo, task]".
  if full_line:sub(value_start, value_start) == "[" then
    local item_start = value_start + 1
    local quote
    for i = value_start + 1, math.min(cursor, #full_line) do
      local char = full_line:sub(i, i)
      if (char == [["]] or char == "'") and full_line:sub(i - 1, i - 1) ~= "\\" then
        if quote == char then
          quote = nil
        elseif quote == nil then
          quote = char
        end
      elseif char == "," and not quote then
        item_start = i + 1
      elseif char == "]" and not quote then
        return nil
      end
    end
    while item_start <= #full_line and full_line:sub(item_start, item_start):match "%s" do
      item_start = item_start + 1
    end

    local item_end = cursor
    for i = cursor + 1, #full_line do
      local char = full_line:sub(i, i)
      if (char == [["]] or char == "'") and full_line:sub(i - 1, i - 1) ~= "\\" then
        if quote == char then
          quote = nil
        elseif quote == nil then
          quote = char
        end
      elseif (char == "," or char == "]") and not quote then
        item_end = i - 1
        break
      else
        item_end = i
      end
    end
    while item_end >= item_start and full_line:sub(item_end, item_end):match "%s" do
      item_end = item_end - 1
    end

    return {
      kind = "value",
      key = key,
      term = completion_term(before:sub(item_start)),
      insert_start = item_start - 1,
      insert_end = math.max(cursor, item_end),
    }
  end

  return {
    kind = "value",
    key = key,
    term = completion_term(before:sub(value_start)),
    insert_start = value_start - 1,
    insert_end = value_end(full_line, cursor, value_start),
  }
end

return M
