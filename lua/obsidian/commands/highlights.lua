local api = require "obsidian.api"
local picker = require "obsidian.picker"
local highlight = require "obsidian.parse.highlight"
local picker_util = require "obsidian.picker.util"
local log = require "obsidian.log"
local Note = require "obsidian.note"

---@param buf integer
local pick_note_highlights = function(buf)
  local note = Note.from_buffer(buf)
  if not note then
    return
  end

  local highlights = {}
  for row, line in ipairs(note.contents) do
    local note_row = row - 1
    vim.list_extend(highlights, highlight.extract(line, { row = note_row }))
  end

  if #highlights == 0 then
    log.info "No highlights in current buffer"
    return
  end

  picker.select(highlights, {
    prompt = "Highlights",
    format_item = function(item)
      return ("%d:%d  %s"):format(item.range.start_row + 1, item.range.start_col + 1, item.text)
    end,
    preview_item = function(item)
      return {
        buf = picker_util.preview_path(tostring(note.path)).buf,
        pos = { item.range.start_row + 1, item.range.start_col + 1 },
        end_pos = { item.range.end_row + 1, item.range.end_col + 1 },
      }
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

return function()
  local buf = vim.api.nvim_get_current_buf()
  pick_note_highlights(buf)
end
