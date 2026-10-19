local api = require "obsidian.api"
local picker = require "obsidian.picker"

return function()
  vim.lsp.buf.document_symbol {
    on_list = picker and function(t)
      picker.select(t.items, {
        prompt = "Table of Contents",
        preview_item = function(entry)
          ---@cast entry obsidian.PickerEntry
          local filename = entry.filename
          ---@cast filename -nil
          local preview = picker.preview_path(filename)
          if entry.lnum then
            preview.pos = { entry.lnum, entry.col and math.max(entry.col - 1, 0) or nil }
          end
          return preview
        end,
      }, function(items)
        local entry = items and items[1]
        if entry then
          api.open_note(entry)
        end
      end)
    end,
  }
end
