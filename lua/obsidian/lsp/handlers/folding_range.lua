local Note = require "obsidian.note"

---@param param lsp.FoldingRangeParams
return function(param, handler)
  ---@type lsp.FoldingRange[]
  local ranges = {}

  local note = Note.from_buffer(0, { collect_sections = true })

  -- Frontmatter fold.
  if note.has_frontmatter and note.frontmatter_end_line then
    local fm_end = note.frontmatter_end_line -- 1-based
    -- Build collapsedText from key: value pairs in the buffer lines.
    local lines = vim.api.nvim_buf_get_lines(0, 0, fm_end, false)
    local parts = {}
    for i = 2, fm_end - 1 do
      local key, val = lines[i] and lines[i]:match "^([%w_%-]+):%s*(.+)$"
      if key and val then
        parts[#parts + 1] = key .. ": " .. val
        if #parts >= 4 then
          parts[#parts + 1] = "…"
          break
        end
      end
    end

    local range = {
      startLine = 0, -- 0-based
      endLine = fm_end - 1, -- 0-based
      kind = "imports",
    }
    if #parts > 0 then
      range.collapsedText = "{ " .. table.concat(parts, ", ") .. " }"
    end
    ranges[#ranges + 1] = range
  end

  -- Heading section folds from note.sections.
  if note.sections then
    for _, section in ipairs(note.sections) do
      local start_line = section.heading.line - 1 -- convert to 0-based
      local end_line = section.end_line - 1 -- convert to 0-based
      if end_line > start_line then
        ranges[#ranges + 1] = {
          startLine = start_line,
          endLine = end_line,
          kind = "region",
        }
      end
    end
  end

  handler(nil, ranges)
end
