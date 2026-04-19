---@param _ lsp.FoldingRangeParams
return function(_, handler)
  ---@type lsp.FoldingRange[]
  local ranges = {}

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local last_line = #lines - 1 -- 0-based

  -- Frontmatter: must start at line 0 with ---
  local content_start = 1 -- 1-based index to start scanning body content
  if lines[1] and lines[1]:match "^%-%-%-+%s*$" then
    local frontmatter_end = nil
    for i = 2, #lines do
      if lines[i]:match "^%-%-%-+%s*$" then
        frontmatter_end = i
        break
      end
    end

    if frontmatter_end then
      local parts = {}
      for i = 2, frontmatter_end - 1 do
        local key, val = lines[i]:match "^([%w_%-]+):%s*(.+)$"
        if key and val then
          parts[#parts + 1] = key .. ": " .. val
          if #parts >= 4 then
            parts[#parts + 1] = "…"
            break
          end
        end
      end

      local range = {
        startLine = 0,
        endLine = frontmatter_end - 1,
        kind = "imports",
      }
      if #parts > 0 then
        range.collapsedText = "{ " .. table.concat(parts, ", ") .. " }"
      end

      ranges[#ranges + 1] = range
      content_start = frontmatter_end + 1
    end
  end

  -- Collect headings (skip lines inside fenced code blocks)
  ---@type { line: integer, level: integer }[]
  local headings = {}
  local in_code_block = false
  for i = content_start, #lines do
    if lines[i]:match "^[`~][`~][`~]" then
      in_code_block = not in_code_block
    end
    if not in_code_block then
      local hashes = lines[i]:match "^(#+)%s+"
      if hashes then
        headings[#headings + 1] = { line = i - 1, level = #hashes } -- 0-based
      end
    end
  end

  -- Emit heading section folds: each heading ends before next heading of same/higher level
  for i = 1, #headings do
    local h = headings[i]
    local end_line = last_line
    for j = i + 1, #headings do
      if headings[j].level <= h.level then
        end_line = headings[j].line - 1
        break
      end
    end
    if end_line > h.line then
      ranges[#ranges + 1] = {
        startLine = h.line,
        endLine = end_line,
        kind = "region",
      }
    end
  end

  handler(nil, ranges)
end
