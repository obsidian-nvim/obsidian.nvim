return function()
  vim.lsp.buf.document_symbol {
    on_list = function(t)
      require("obsidian.picker").pick(t.items, {
        prompt_title = "Table of Contents",
      })
    end,
  }
end
