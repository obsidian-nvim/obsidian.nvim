return function()
  vim.lsp.buf.document_symbol {
    on_list = Obsidian.picker and function(t)
      local items = vim.tbl_map(function(value)
        value.display = value.text:sub(7)
        return value
      end, t.items)
      Obsidian.picker.pick(items, {
        prompt_title = "Table of Contents",
        format_item = function(v)
          return v.display
        end,
        callback = function(v)
          vim.api.nvim_win_set_cursor(0, { v.lnum, 0 })
        end,
      })
    end,
  }
end
