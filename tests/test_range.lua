local Pos = require "obsidian.pos"
local Range = require "obsidian.range"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["constructs flat ranges and independent endpoint positions"] = function()
  local start, finish = Pos.new(1, 2), Pos.new(3, 4)
  local range = Range.from_positions(start, finish)
  eq(range, Range.new(1, 2, 3, 4))
  eq(Range.start_pos(range), start)
  eq(Range.end_pos(range), finish)
  start.col = 0
  eq(range.start_col, 2)
  eq(pcall(Range.new, 2, 0, 1, 4), false)
  eq(pcall(Range.new, 0, 3, 0, 2), false)
  eq(pcall(Range.new, -1, 0, 0, 0), false)
end

T["uses half-open position containment"] = function()
  local range = Range.new(1, 2, 3, 4)
  eq(Range.contains_pos(range, Pos.new(1, 1)), false)
  eq(Range.contains_pos(range, Pos.new(1, 2)), true)
  eq(Range.contains_pos(range, Pos.new(2, 0)), true)
  eq(Range.contains_pos(range, Pos.new(3, 3)), true)
  eq(Range.contains_pos(range, Pos.new(3, 4)), false)
  local empty = Range.new(1, 2, 1, 2)
  eq(Range.is_empty(empty), true)
  eq(Range.contains_pos(empty, Pos.new(1, 2)), false)
end

T["encloses empty ranges at either endpoint"] = function()
  local range = Range.new(1, 2, 3, 4)
  eq(Range.contains_range(range, range), true)
  eq(Range.contains_range(range, Range.new(1, 2, 1, 2)), true)
  eq(Range.contains_range(range, Range.new(3, 4, 3, 4)), true)
  eq(Range.contains_range(range, Range.new(3, 4, 3, 5)), false)
  local empty = Range.new(1, 2, 1, 2)
  eq(Range.contains_range(empty, empty), true)
end

T["intersects only nonempty overlaps"] = function()
  local a, b = Range.new(0, 2, 2, 0), Range.new(1, 3, 3, 0)
  eq(Range.intersection(a, b), Range.new(1, 3, 2, 0))
  eq(Range.intersection(b, a), Range.intersection(a, b))
  eq(Range.intersection(a, a), a)
  eq(Range.intersection(a, Range.new(2, 0, 3, 0)), nil)
  eq(Range.intersection(a, Range.new(1, 0, 1, 0)), nil)
end

T["operates on serialized plain tables"] = function()
  local range = Range.new(0, 1, 1, 0)
  vim.b.obsidian_test_range = range
  local decoded = vim.b.obsidian_test_range
  eq(getmetatable(decoded), nil)
  eq(Range.contains_pos(decoded, Pos.new(0, 1)), true)
  eq(Range.intersection(decoded, range), range)
  vim.b.obsidian_test_range = nil
end

T["converts LSP ranges with explicit encoding"] = function()
  local lines = { "é😀tag", "éfin" }
  local range = Range.new(0, 6, 1, 2)
  local lsp = { start = { line = 0, character = 3 }, ["end"] = { line = 1, character = 1 } }
  eq(Range.to_lsp(range, "utf-16", lines), lsp)
  eq(Range.from_lsp(lsp, "utf-16", lines), range)
  eq(pcall(Range.to_lsp, range), false)
  local whole_lines = Range.new(0, 0, 2, 0)
  eq(Range.from_lsp(Range.to_lsp(whole_lines, "utf-16"), "utf-16"), whole_lines)
end

T["attaches a buffer without changing the snapshot range"] = function()
  if not vim.range then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local range = Range.new(0, 0, 1, 0)
  local bound = Range.to_vim(range, buf)
  eq({ bound.buf, bound.start_row, bound.start_col, bound.end_row, bound.end_col }, { buf, 0, 0, 1, 0 })
  eq(range.buf, nil)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
