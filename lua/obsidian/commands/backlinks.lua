return function()
  local picker = Obsidian.picker

  vim.lsp.buf.references(nil, {
    on_list = not picker.state._native and function(t)
      picker.pick(t.items, { prompt_title = "Backlinks" })
    end or nil,
  })
end
