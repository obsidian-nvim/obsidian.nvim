local log = require "obsidian.log"
local api = require "obsidian.api"
local picker = require "obsidian.picker"
local actions = require "obsidian.actions"
local link_suggestion = require "obsidian.note.link_suggestion"
local util = require "obsidian.util"

return function()
  local bufnr = vim.api.nvim_get_current_buf()
  local note = api.current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
  if not note then
    return log.info "Not in a note"
  end

  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    return log.warn "Cache is not enabled; cannot search for unlinked mentions"
  end

  local suggestions = link_suggestion.find(note)
  if #suggestions == 0 then
    return log.info "No unlinked outgoing mentions found"
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  ---@type table<integer, obsidian.LinkSuggestion>
  local entry_suggestions = {}

  for _, suggestion in ipairs(suggestions) do
    for _, candidate in ipairs(suggestion.candidates) do
      local idx = #entries + 1
      local lnum = suggestion.range.start_row + 1
      local col = suggestion.range.start_col + 1
      local entry = {
        filename = tostring(note.path),
        lnum = lnum,
        col = col,
        text = string.format(
          "%s:%d:%d  %s → %s",
          vim.fn.fnamemodify(tostring(note.path), ":t"),
          lnum,
          col,
          suggestion.text,
          candidate.new_text
        ),
        user_data = { suggestion = suggestion, candidate = candidate },
      }
      entries[idx] = entry
      entry_suggestions[idx] = suggestion
    end
  end

  picker.select(entries, {
    prompt = "Outgoing unlinked mentions",
    allow_multiple = true,
    preview_item = function(entry)
      ---@cast entry obsidian.PickerEntry
      local preview = util.preview_path(entry.filename)
      preview.pos = { entry.lnum or 1, entry.col and math.max(entry.col - 1, 0) or 0 }
      return preview
    end,
  }, function(choices)
    if not choices then
      return
    end
    for _, choice in ipairs(choices) do
      ---@cast choice obsidian.PickerEntry
      local data = choice.user_data
      if data then
        actions.link_suggestion(data.suggestion)
      end
    end
  end)
end
