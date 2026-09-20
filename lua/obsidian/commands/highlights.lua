local api = require "obsidian.api"
local picker = require "obsidian.picker"

---@param bufnr integer
---@param item obsidian.HighlightMatch
---@return obsidian.ui_select_preview_spec
local function preview(bufnr, item)
  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

  local range = item.range
  return {
    buf = preview_buf,
    pos = { range.start_row + 1, range.start_col },
    pos_end = { range.end_row + 1, range.end_col },
  }
end

return function()
  local buf = vim.api.nvim_get_current_buf()
  local note = api.current_note(buf)
  if not note then
    return
  end

  local highlights = note:highlights()
  if #highlights == 0 then
    return
  end

  picker.select(highlights, {
    prompt = "Highlights",
    format_item = function(item)
      return ("%d:%d  %s"):format(item.range.start_row + 1, item.range.start_col + 1, item.text)
    end,
    preview_item = function(item)
      return preview(buf, item)
    end,
  }, function(items)
    local item = items and items[1]
    if not item or not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local range = item.range
    api.open_note {
      filename = vim.api.nvim_buf_get_name(buf),
      lnum = range.start_row + 1,
      col = range.start_col + 1,
      end_lnum = range.end_row + 1,
      end_col = range.end_col + 1,
    }
  end)
end
