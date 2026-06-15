local Note = require "obsidian.note"

---@param params lsp.FoldingRangeParams
return function(params, handler)
  ---@type lsp.FoldingRange[]
  local ranges = {}

  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local note = Note.from_buffer(bufnr, { collect_sections = true })

  -- Frontmatter fold.
  if note.has_frontmatter and note.frontmatter_end_line then
    local fm_end = note.frontmatter_end_line -- 1-based
    local range = {
      startLine = 0,
      endLine = fm_end - 1, -- 0-based
      kind = "imports",
      collapsedText = "Properties",
    }
    ranges[#ranges + 1] = range
  end

  -- Heading section folds from note.sections.
  if note.sections then
    for _, section in ipairs(note.sections) do
      if section.header then
        local start_line = section.heading_range.start_row
        local end_line = section.range.end_row - 1
        if end_line > start_line then
          ranges[#ranges + 1] = {
            startLine = start_line,
            endLine = end_line,
            kind = "region",
          }
        end
      end
    end
  end

  handler(nil, ranges)
end
