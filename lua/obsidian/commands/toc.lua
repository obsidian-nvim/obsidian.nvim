return function()
  ---@diagnostic disable-next-line: missing-fields,param-type-mismatch
  vim.lsp.buf.document_symbol {
    on_list = Obsidian.picker and function(t)
      Obsidian.picker.pick(t.items, {
        prompt_title = "Table of Contents",
      })
    end,
  }
end
