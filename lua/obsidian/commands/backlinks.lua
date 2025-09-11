return function()
  local picker = Obsidian.picker

  vim.lsp.buf.references(nil, {
    on_list = picker and function(t)
      picker:pick(t.items, {
        prompt_title = "Backlinks",
        callback = function(v)
          require("obsidian.api").open_buffer(v.filename, { col = v.col, line = v.lnum })
        end,
      })
    end,
  })
end
