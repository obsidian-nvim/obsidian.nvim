return function()
  local pos = vim.pos and vim.pos.cursor and vim.pos.cursor(0)
  ---@cast pos -nil
  vim.lsp.buf.document_symbol {
    on_list = Obsidian.picker and function(t)
      Obsidian.picker.pick(t.items, {
        prompt_title = "Table of Contents",
      })
    end,
    pos = pos,
  }
end
