local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local api = require "obsidian.api"
local header = require "obsidian.parse.header"
local parse_block_id = require "obsidian.parse.block_id"
local tags = require "obsidian.tag"
local util = require "obsidian.util.rename"

local M = {}

---@class obsidian.lsp.RenameTarget
---@field kind "note"|"block"|"heading"|"footnote"|"tag"|"attachment"
---@field bufnr integer
---@field range lsp.Range -- text replaced in bufnr (utf-8 byte columns)
---@field placeholder string
---@field ref obsidian.parse.Ref|? -- kind == "note": the link under the cursor
---@field id string|? -- block id without "^", footnote name
---@field anchor string|? -- normalized "#anchor"

--- Buffer and position of a rename request, defaulting to the current buffer and cursor.
---@param params { textDocument: lsp.TextDocumentIdentifier|?, position: lsp.Position|? }|?
---@return integer bufnr
---@return lsp.Position position
M.resolve_params = function(params)
  params = params or {}
  local bufnr = params.textDocument and vim.uri_to_bufnr(params.textDocument.uri) or vim.api.nvim_get_current_buf()
  local position = params.position
  if not position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { line = cursor[1] - 1, character = cursor[2] }
  end
  return bufnr, position
end

---@param ref obsidian.parse.Ref
---@param bufnr integer
---@param row integer
---@return obsidian.lsp.RenameTarget|?
local function link_target(ref, bufnr, row)
  if ref.kind == "footnote" then
    return {
      kind = "footnote",
      bufnr = bufnr,
      id = ref.target,
      placeholder = ref.target,
      range = util.range(row, ref.range.start_col + 2, ref.range.end_col - 1),
    }
  end

  if ref.kind ~= "wiki" and ref.kind ~= "markdown" then
    return nil
  end

  local components = util.fragment_components(ref)
  local last = components[#components]

  if ref.target == "" and ref.block and last then
    return {
      kind = "block",
      bufnr = bufnr,
      id = ref.block,
      placeholder = ref.block,
      range = util.range(row, last.col + 1, last.col + #last.text),
    }
  end

  if ref.target == "" and ref.anchor and last then
    return {
      kind = "heading",
      bufnr = bufnr,
      anchor = header.normalize_anchor(vim.uri_decode(last.text)),
      placeholder = last.text,
      range = util.range(row, last.col, last.col + #last.text),
    }
  end

  if ref.target ~= "" then
    local open = ref.kind == "wiki" and (ref.embed and 3 or 2) or select(2, ref.raw:find("](", 1, true))
    local s = open and ref.raw:find(ref.target, open + 1, true)
    if not s then
      return nil
    end
    local col = ref.range.start_col + s - 1
    local is_attachment = api.is_attachment_path(ref.target)
    return {
      kind = is_attachment and "attachment" or "note",
      bufnr = bufnr,
      ref = ref,
      placeholder = is_attachment and vim.fs.basename(vim.uri_decode(ref.target)) or ref.target,
      range = util.range(row, col, col + #ref.target),
    }
  end
end

--- Find what a rename request at `position` acts on.
---@param bufnr integer
---@param position lsp.Position
---@return obsidian.lsp.RenameTarget|?
M.target_at = function(bufnr, position)
  local row, cur_col = position.line, position.character
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local document = BufferDocument.get(bufnr)

  local _, kind, _, ref = api.cursor_link(bufnr, position)
  if kind and ref then
    return link_target(ref, bufnr, row)
  end

  -- Inline `#tag` and `tags:` entries of the frontmatter.
  for _, occurrence in ipairs(tags.extract(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { document = document })) do
    local r = occurrence.range
    if r.start_row == row and r.start_col <= cur_col and cur_col < r.end_col then
      return {
        kind = "tag",
        bufnr = bufnr,
        id = occurrence.tag,
        placeholder = occurrence.tag,
        range = util.range(row, occurrence.source == "inline" and r.start_col + 1 or r.start_col, r.end_col),
      }
    end
  end

  for _, block in ipairs(parse_block_id.extract(line, { row = row, lexical = true })) do
    if
      block.range.start_col <= cur_col
      and cur_col < block.range.end_col
      and not document:intersects(block.range, Document.BODY_EXCLUSIONS)
    then
      return {
        kind = "block",
        bufnr = bufnr,
        id = block.raw:sub(2),
        placeholder = block.raw:sub(2),
        range = util.range(row, block.range.start_col + 1, block.range.end_col),
      }
    end
  end

  for _, heading in ipairs(require("obsidian.header").headings(bufnr)) do
    if heading.row <= row and row <= heading.last_row then
      return {
        kind = "heading",
        bufnr = bufnr,
        anchor = heading.anchor,
        placeholder = heading.text,
        range = util.range(heading.row, heading.start_col, heading.end_col),
      }
    end
  end
end

return M
