return function()
  local picker = Obsidian.picker
  vim.lsp.buf.references({ includeDeclaration = false }, { on_list = picker and picker:qf_on_list "Backlinks" })
end
