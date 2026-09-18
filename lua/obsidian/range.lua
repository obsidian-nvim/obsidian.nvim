--- Half-open byte ranges within a document snapshot: [start, end).
--- Independent of Neovim's buffer-bound vim.Range, with the same indexing conventions.
--- Values are immutable by convention; compare only ranges from the same snapshot.
--- Use module functions because serialization (including vim.b) may discard metatables.
--- Line ranges may end at (line_count, 0); adapters must handle this sentinel explicitly.
local Pos = require "obsidian.pos"

---@class obsidian.Range
---@field start_row integer 0-based start row.
---@field start_col integer 0-based start byte offset.
---@field end_row integer 0-based end row.
---@field end_col integer 0-based exclusive end byte offset.
local Range = {}
Range.__index = Range

---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@return obsidian.Range
Range.new = function(start_row, start_col, end_row, end_col)
  local start = Pos.new(start_row, start_col)
  local finish = Pos.new(end_row, end_col)
  assert(Pos.compare(start, finish) <= 0, "range start must not follow its end")
  return setmetatable({
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }, Range)
end

---@param start obsidian.Pos
---@param finish obsidian.Pos
---@return obsidian.Range
Range.from_positions = function(start, finish)
  return Range.new(start.row, start.col, finish.row, finish.col)
end

---@param range obsidian.Range
---@return obsidian.Pos
Range.start_pos = function(range)
  return Pos.new(range.start_row, range.start_col)
end

---@param range obsidian.Range
---@return obsidian.Pos
Range.end_pos = function(range)
  return Pos.new(range.end_row, range.end_col)
end

---@param range obsidian.Range
---@return boolean
Range.is_empty = function(range)
  return range.start_row == range.end_row and range.start_col == range.end_col
end

--- Empty ranges contain no positions; the exclusive end is never inside.
---@param range obsidian.Range
---@param pos obsidian.Pos
---@return boolean
Range.contains_pos = function(range, pos)
  return Pos.compare(Range.start_pos(range), pos) <= 0 and Pos.compare(pos, Range.end_pos(range)) < 0
end

--- Endpoint enclosure, including empty inner ranges at either boundary.
---@param outer obsidian.Range
---@param inner obsidian.Range
---@return boolean
Range.contains_range = function(outer, inner)
  return Pos.compare(Range.start_pos(outer), Range.start_pos(inner)) <= 0
    and Pos.compare(Range.end_pos(inner), Range.end_pos(outer)) <= 0
end

--- Return the nonempty intersection; touching ranges do not intersect.
---@param a obsidian.Range
---@param b obsidian.Range
---@return obsidian.Range?
Range.intersection = function(a, b)
  local a_start, b_start = Range.start_pos(a), Range.start_pos(b)
  local a_end, b_end = Range.end_pos(a), Range.end_pos(b)
  local start = Pos.compare(a_start, b_start) < 0 and b_start or a_start
  local finish = Pos.compare(a_end, b_end) < 0 and a_end or b_end
  if Pos.compare(start, finish) < 0 then
    return Range.from_positions(start, finish)
  end
end

--- Attach a buffer explicitly. The caller must ensure it matches the snapshot.
--- Requires a Neovim version providing vim.range.
---@param range obsidian.Range
---@param bufnr integer
---@return vim.Range
Range.to_vim = function(range, bufnr)
  if vim.fn.has "nvim-0.13" == 1 then
    local new = vim.range
    ---@cast new fun(buf: integer, sr: integer, sc: integer, er: integer, ec: integer): vim.Range
    return new(bufnr, range.start_row, range.start_col, range.end_row, range.end_col)
  end

  local new = vim.range --[[@as any]]
  return new(range.start_row, range.start_col, range.end_row, range.end_col, { buf = bufnr })
end

---@param range obsidian.Range
---@param encoding lsp.PositionEncodingKind
---@param lines string[]?
---@return lsp.Range
Range.to_lsp = function(range, encoding, lines)
  return {
    start = Pos.to_lsp(Range.start_pos(range), encoding, lines),
    ["end"] = Pos.to_lsp(Range.end_pos(range), encoding, lines),
  }
end

---@param range lsp.Range
---@param encoding lsp.PositionEncodingKind
---@param lines string[]?
---@return obsidian.Range
Range.from_lsp = function(range, encoding, lines)
  return Range.from_positions(Pos.from_lsp(range.start, encoding, lines), Pos.from_lsp(range["end"], encoding, lines))
end

setmetatable(Range, {
  __call = function(_, ...)
    return Range.new(...)
  end,
})

return Range
