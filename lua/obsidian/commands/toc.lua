local api = require "obsidian.api"
local picker = require "obsidian.picker"

return function()
  local pos = vim.pos and vim.pos.cursor and vim.pos.cursor(0)
  ---@cast pos -nil
  vim.lsp.buf.document_symbol {
    on_list = picker and function(t)
      picker.select(t.items, { prompt = "Table of Contents" }, function(items)
        local entry = items and items[1]
        if entry then
          api.open_note(entry)
        end
      end)
    end,
    pos = pos,
  }
end
