local api = require "obsidian.api"

return function()
  local buf = vim.api.nvim_get_current_buf()
  local note = api.current_note(buf)
  if not note then
    return
  end

  local highlights = note:highlights()
  require("obsidian.picker").select(highlights, {
    format_item = function(item)
      return item.text
    end,
  }, function(items)
    if vim.tbl_isempty(items) then
      return
    end
    local item = items[1]
    ---@type obsidian.Range
    local rge = item.range
    api.open_note {
      filename = vim.api.nvim_buf_get_name(buf),
      lnum = rge.start_row + 1,
      col = rge.start_col + 1,
      end_col = rge.end_col + 1,
    }
  end)
end
