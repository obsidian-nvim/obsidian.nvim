local obsidian = require "obsidian"
return function()
  vim.lsp.buf.document_symbol {
    on_list = Obsidian.picker and function(t)
      Obsidian.picker.pick(t.items, { prompt = "Table of Contents" }, obsidian.api.open_note)
    end,
  }
end
