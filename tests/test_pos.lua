local Pos = require "obsidian.pos"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["compares document coordinates lexicographically"] = function()
  eq(Pos.compare(Pos.new(1, 20), Pos.new(2, 0)), -1)
  eq(Pos.compare(Pos.new(2, 1), Pos.new(2, 0)), 1)
  eq(Pos.compare(Pos.new(2, 1), { row = 2, col = 1 }), 0)
end

T["rejects invalid coordinates"] = function()
  for _, args in ipairs { { -1, 0 }, { 0, -1 }, { 0.5, 0 }, { 0, 1.5 }, { math.huge, 0 } } do
    eq(pcall(Pos.new, unpack(args)), false)
  end
end

T["converts cursor tuples without reading a window"] = function()
  eq(Pos.from_cursor { 3, 7 }, Pos.new(2, 7))
  eq(Pos.to_cursor { row = 0, col = 0 }, { 1, 0 })
end

T["survives serialization"] = function()
  local pos = vim.json.decode(vim.json.encode(Pos.new(3, 8)))
  eq(getmetatable(pos), nil)
  eq(Pos.compare(pos, Pos.new(3, 8)), 0)
  vim.b.obsidian_test_pos = pos
  eq(Pos.to_cursor(vim.b.obsidian_test_pos), { 4, 8 })
  vim.b.obsidian_test_pos = nil
end

T["converts Unicode positions using explicit source lines and encoding"] = function()
  local lines = { "é😀tag" }
  local pos = Pos.new(0, 6)
  for encoding, col in pairs { ["utf-8"] = 6, ["utf-16"] = 3, ["utf-32"] = 2 } do
    local lsp = { line = 0, character = col }
    eq(Pos.to_lsp(pos, encoding, lines), lsp)
    eq(Pos.from_lsp(lsp, encoding, lines), pos)
  end
  eq(pcall(Pos.to_lsp, pos), false)
  eq(pcall(Pos.to_lsp, pos, "utf-16"), false)
  eq(pcall(Pos.from_lsp, { line = 0, character = 3 }, "utf-16"), false)
  eq(Pos.to_lsp(Pos.new(1, 0), "utf-16"), { line = 1, character = 0 })
end

T["attaches the supplied buffer only at the Neovim boundary"] = function()
  if not vim.pos then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local pos = Pos.new(0, 0)
  local bound = Pos.to_vim(pos, buf)
  eq({ bound.buf, bound.row, bound.col }, { buf, 0, 0 })
  eq(pos.buf, nil)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
