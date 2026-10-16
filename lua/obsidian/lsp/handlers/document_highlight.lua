local Pos = require "obsidian.pos"
local Range = require "obsidian.range"
local tags = require "obsidian.tag"

---@param params lsp.DocumentHighlightParams
---@param handler fun(_: any, highlights: lsp.DocumentHighlight[])
return function(params, handler)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local note = require("obsidian.note").from_buffer(bufnr)
  local lines = assert(note.raw_contents, "buffer note is missing source lines")
  local position = Pos.from_lsp(params.position, "utf-8", lines)

  if not note.frontmatter_end_line or position.row <= 0 or position.row >= note.frontmatter_end_line then
    return handler(nil, {})
  end

  local frontmatter_lines = vim.list_slice(lines, 1, note.frontmatter_end_line)
  for _, occurrence in
    ipairs(tags.extract(frontmatter_lines, {
      frontmatter_end_line = note.frontmatter_end_line,
      frontmatter_elements = note.frontmatter_elements,
    }))
  do
    if occurrence.source ~= "frontmatter" then
      break
    elseif Range.contains_pos(occurrence.range, position) then
      return handler(nil, {
        {
          range = Range.to_lsp(occurrence.range, "utf-8", lines),
          kind = vim.lsp.protocol.DocumentHighlightKind.Text,
        },
      })
    end
  end

  handler(nil, {})
end
