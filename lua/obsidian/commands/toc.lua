return function()
  local picker = assert(Obsidian.picker)
  vim.lsp.buf.document_symbol {
    on_list = picker and function(t)
      local items = vim.tbl_map(function(value)
        value.display = value.text:sub(7)
        return value
      end, t.items)
      picker:pick(items, {
        prompt_title = "Table of Contents",
        callback = function(v)
          vim.api.nvim_win_set_cursor(0, { v.line, 0 })
        end,
      })
    end,
  }
end
