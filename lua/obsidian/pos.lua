--- Coordinates within a document snapshot, independent of buffers and paths.
--- Values are immutable by convention. Compare only positions from the same snapshot.
--- Use module functions: serialization (including vim.b) may discard metatables.
---
---@class obsidian.Pos
---@field row integer 0-based line index.
---@field col integer 0-based byte offset within the line (not a display column).
local Pos = {}
Pos.__index = Pos

---@param row integer
---@param col integer
---@return obsidian.Pos
Pos.new = function(row, col)
  assert(type(row) == "number" and row >= 0 and row % 1 == 0, "row must be a nonnegative integer")
  assert(type(col) == "number" and col >= 0 and col % 1 == 0, "col must be a nonnegative integer")
  return setmetatable({ row = row, col = col }, Pos)
end

---@param a obsidian.Pos
---@param b obsidian.Pos
---@return -1|0|1
Pos.compare = function(a, b)
  if a.row == b.row and a.col == b.col then
    return 0
  elseif a.row < b.row or (a.row == b.row and a.col < b.col) then
    return -1
  else
    return 1
  end
end

--- Convert a cursor tuple; does not read the current window.
---@param cursor { [1]: integer, [2]: integer } (1-based row, 0-based byte column).
---@return obsidian.Pos
Pos.from_cursor = function(cursor)
  local row = cursor[1] - 1
  ---@cast row integer
  return Pos.new(row, cursor[2])
end

---@param pos obsidian.Pos
---@return { [1]: integer, [2]: integer }
Pos.to_cursor = function(pos)
  return { pos.row + 1, pos.col }
end

--- Attach a buffer explicitly. The caller must ensure it matches the snapshot.
--- Requires a Neovim version providing vim.pos.
---@param pos obsidian.Pos
---@param bufnr integer
---@return vim.Pos
Pos.to_vim = function(pos, bufnr)
  local new = vim.pos --[[@as fun(buf: integer, row: integer, col: integer): vim.Pos]]
  return new(bufnr, pos.row, pos.col)
end

---@param encoding lsp.PositionEncodingKind
local function validate_encoding(encoding)
  assert(encoding == "utf-8" or encoding == "utf-16" or encoding == "utf-32", "explicit position encoding required")
end

--- Convert to LSP coordinates. Nonzero UTF-16/32 columns require source lines.
--- A (line_count, 0) line-range sentinel is preserved, not clamped to text EOF.
---@param pos obsidian.Pos
---@param encoding lsp.PositionEncodingKind
---@param lines string[]?
---@return lsp.Position
Pos.to_lsp = function(pos, encoding, lines)
  validate_encoding(encoding)
  local col = pos.col
  if col ~= 0 and encoding ~= "utf-8" then
    local line = assert(lines and lines[pos.row + 1], "source line required for position conversion")
    col = vim.str_utfindex(line, encoding, col, true)
  end
  return { line = pos.row, character = col }
end

---@param pos lsp.Position
---@param encoding lsp.PositionEncodingKind
---@param lines string[]?
---@return obsidian.Pos
Pos.from_lsp = function(pos, encoding, lines)
  validate_encoding(encoding)
  local col = pos.character
  if col ~= 0 and encoding ~= "utf-8" then
    local line = assert(lines and lines[pos.line + 1], "source line required for position conversion")
    col = vim.str_byteindex(line, encoding, col, true)
  end
  ---@cast col integer
  return Pos.new(pos.line, col)
end

setmetatable(Pos, {
  __call = function(_, ...)
    return Pos.new(...)
  end,
})

return Pos
