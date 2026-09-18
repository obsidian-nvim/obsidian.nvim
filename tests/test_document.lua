local BufferDocument = require "obsidian.document"
local Pos = require "obsidian.pos"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["caches one parsed snapshot per buffer changedtick"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "text", "```", "code", "```" })

  local first = BufferDocument.get(buf)
  eq(BufferDocument.get(buf), first)
  eq(first:context_at(Pos.new(2, 0)).code_block ~= nil, true)

  vim.api.nvim_buf_set_lines(buf, 1, -1, false, { "prose" })
  local second = BufferDocument.get(buf)
  eq(second == first, false)
  eq(second:context_at(Pos.new(1, 0)).code_block, nil)

  BufferDocument.invalidate(buf)
  eq(BufferDocument.get(buf) == second, false)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
