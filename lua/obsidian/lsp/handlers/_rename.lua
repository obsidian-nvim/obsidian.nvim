local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local api = require "obsidian.api"
local header = require "obsidian.parse.header"
local parse_block_id = require "obsidian.parse.block_id"

local M = {}

---@class obsidian.lsp.RenameTarget
---@field kind "note"|"block"|"heading"|"footnote"
---@field bufnr integer
---@field range lsp.Range -- text replaced in bufnr (utf-8 byte columns)
---@field placeholder string
---@field ref obsidian.parse.Ref|? -- kind == "note": the link under the cursor
---@field id string|? -- block id without "^", footnote name
---@field header string|? -- heading text; nil when coming from `[[#Heading]]`
---@field anchor string|? -- normalized "#anchor"

---@param row integer
---@param start_col integer
---@param end_col integer
---@return lsp.Range
local function range(row, start_col, end_col)
  return {
    start = { line = row, character = start_col },
    ["end"] = { line = row, character = end_col },
  }
end

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

--- The `#`-separated fragment components of a wiki/markdown ref, with absolute
--- 0-indexed byte columns. A block component is the one starting with `^`.
---@param ref obsidian.parse.Ref
---@return { text: string, col: integer }[]
M.fragment_components = function(ref)
  local raw = ref.raw
  local from, to
  if ref.kind == "wiki" then
    from = raw:find("#", ref.embed and 4 or 3, true)
    local pipe = from and raw:find("|", from, true)
    to = (pipe or #raw - 1) - 1
  else
    -- The markdown label may contain `#`, so start after `](`.
    local paren = raw:find("](", 1, true)
    from = paren and raw:find("#", paren + 2, true)
    to = #raw - 1
  end

  local out = {}
  if not from then
    return out
  end
  local pos = from + 1
  while pos <= to + 1 do
    local nxt = raw:find("#", pos, true)
    if not nxt or nxt > to then
      nxt = to + 1
    end
    if nxt > pos then
      out[#out + 1] = { text = raw:sub(pos, nxt - 1), col = ref.range.start_col + pos - 1 }
    end
    pos = nxt + 1
  end
  return out
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
      range = range(row, ref.range.start_col + 2, ref.range.end_col - 1),
    }
  end

  if ref.kind ~= "wiki" and ref.kind ~= "markdown" then
    return nil
  end

  local last = M.fragment_components(ref)
  last = last[#last]

  if ref.target == "" and ref.block and last then
    return {
      kind = "block",
      bufnr = bufnr,
      id = ref.block,
      placeholder = ref.block,
      range = range(row, last.col + 1, last.col + #last.text),
    }
  end

  if ref.target == "" and ref.anchor and last then
    return {
      kind = "heading",
      bufnr = bufnr,
      anchor = header.normalize_anchor(vim.uri_decode(last.text)),
      placeholder = last.text,
      range = range(row, last.col, last.col + #last.text),
    }
  end

  if ref.target ~= "" then
    local open = ref.kind == "wiki" and (ref.embed and 3 or 2) or select(2, ref.raw:find("](", 1, true))
    local s = open and ref.raw:find(ref.target, open + 1, true)
    if not s then
      return nil
    end
    local col = ref.range.start_col + s - 1
    return {
      kind = "note",
      bufnr = bufnr,
      ref = ref,
      placeholder = ref.target,
      range = range(row, col, col + #ref.target),
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
        range = range(row, block.range.start_col + 1, block.range.end_col),
      }
    end
  end

  local parsed = header.parse(line)
  local first_byte = line:find "%S"
  if parsed and first_byte then
    local marker = Range.new(row, first_byte - 1, row, first_byte)
    if not document:intersects(marker, Document.BODY_EXCLUSIONS) then
      local s, e = line:find(parsed.header, parsed.level + 1, true)
      return {
        kind = "heading",
        bufnr = bufnr,
        header = parsed.header,
        anchor = parsed.anchor,
        placeholder = parsed.header,
        range = range(row, s - 1, e),
      }
    end
  end
end

return M
