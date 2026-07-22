local M = {}

---@class obsidian.completion.FragmentContext
---@field style "wiki"|"markdown"
---@field ref string
---@field label string|?
---@field fragment string
---@field insert_start integer
---@field insert_end integer
---@field filter_prefix string

---Parse the link around the cursor while a fragment is being entered.
---@param request obsidian.completion.Request
---@return obsidian.completion.FragmentContext|?
function M.parse(request)
  local before = request.cursor_before_line
  local after = request.cursor_after_line

  -- Wiki link: [[ref#fragment|label]], with the cursor before the alias/closing brackets.
  local link_start
  local from = 1
  while true do
    local pos = before:find("[[", from, true)
    if not pos then
      break
    end
    link_start = pos
    from = pos + 2
  end

  if link_start then
    local content = before:sub(link_start + 2)
    if not content:find("]", 1, true) then
      local hash = content:find("#", 1, true)
      if hash then
        local tail = after:match "^([^%]]*)%]%]"
        local label
        local insert_end = request.character
        if tail ~= nil and (tail == "" or vim.startswith(tail, "|")) then
          label = tail ~= "" and tail:sub(2) or nil
          insert_end = insert_end + #tail + 2
        end

        ---@type obsidian.completion.FragmentContext
        local context = {
          style = "wiki",
          ref = content:sub(1, hash - 1),
          label = label,
          fragment = content:sub(hash),
          insert_start = link_start - 1,
          insert_end = insert_end,
          filter_prefix = before:sub(link_start),
        }
        return context
      end
    end
  end

  -- Markdown link: [label](path#fragment), with the cursor before the closing parenthesis.
  local target_start
  from = 1
  while true do
    local pos = before:find("](", from, true)
    if not pos then
      break
    end
    target_start = pos
    from = pos + 2
  end

  if target_start then
    local target = before:sub(target_start + 2)
    if not target:find(")", 1, true) then
      local hash = target:find("#", 1, true)
      if hash then
        local label_start
        for i = target_start - 1, 1, -1 do
          if before:sub(i, i) == "[" then
            label_start = i
            break
          elseif before:sub(i, i) == "]" then
            break
          end
        end

        if label_start then
          ---@cast label_start integer
          ---@type obsidian.completion.FragmentContext
          local context = {
            style = "markdown",
            ref = target:sub(1, hash - 1),
            label = before:sub(label_start + 1, target_start - 1),
            fragment = target:sub(hash),
            insert_start = label_start - 1,
            insert_end = request.character + (vim.startswith(after, ")") and 1 or 0),
            filter_prefix = before:sub(label_start),
          }
          return context
        end
      end
    end
  end

  return nil
end

---Turn a completed link into a snippet whose final cursor is where a fragment belongs.
---@param link string
---@return string|? snippet
function M.chainable_snippet(link)
  local insertion
  if vim.startswith(link, "[[") and vim.endswith(link, "]]") then
    insertion = link:find("|", 1, true) or (#link - 1)
  elseif vim.startswith(link, "[") and vim.endswith(link, ")") then
    insertion = #link
  else
    return nil
  end

  local function escape(text)
    return text:gsub("\\", "\\\\"):gsub("%$", "\\$"):gsub("}", "\\}")
  end

  return escape(link:sub(1, insertion - 1)) .. "$0" .. escape(link:sub(insertion))
end

return M
