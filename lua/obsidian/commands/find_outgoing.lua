local log = require "obsidian.log"
local api = require "obsidian.api"
local picker = require "obsidian.picker"
local actions = require "obsidian.actions"
local link_suggestion = require "obsidian.note.link_suggestion"
local util = require "obsidian.util"
local Path = require "obsidian.path"

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

  ---@type table<string, obsidian.PickerEntry>
  local targets = {}

  for _, suggestion in ipairs(suggestions) do
    for _, candidate in ipairs(suggestion.candidates) do
      local target = targets[candidate.target_path]
      if not target then
        target = {
          filename = candidate.target_path,
          text = tostring(Path.new(candidate.target_path):vault_relative_path()),
          user_data = { locations = {} },
        }
        targets[candidate.target_path] = target
      end
      local lnum = suggestion.range.start_row + 1
      local col = suggestion.range.start_col + 1
      target.user_data.locations[#target.user_data.locations + 1] = {
        filename = tostring(note.path),
        lnum = lnum,
        col = col,
        text = string.format("%s:%d:%d  %s → %s", vim.fn.fnamemodify(tostring(note.path), ":t"), lnum, col, suggestion.text, candidate.new_text),
        user_data = { suggestion = suggestion, candidate = candidate },
      }
    end
  end

  local entries = vim.tbl_values(targets)
  table.sort(entries, function(a, b)
    return a.filename < b.filename
  end)

  picker.select(entries, {
    prompt = "Outgoing link targets",
    preview_item = function(entry)
      ---@cast entry obsidian.PickerEntry
      local preview = util.preview_path(entry.filename)
      return preview
    end,
  }, function(choices)
    local target = choices and choices[1]
    local locations = target and target.user_data and target.user_data.locations
    if not locations then
      return
    end
    picker.select(locations, {
      prompt = "Outgoing locations",
      allow_multiple = true,
      preview_item = function(entry)
        local preview = util.preview_path(entry.filename)
        preview.pos = { entry.lnum or 1, entry.col and math.max(entry.col - 1, 0) or 0 }
        return preview
      end,
    }, function(location_choices)
      for _, choice in ipairs(location_choices or {}) do
        local data = choice.user_data
        if data then
          actions.link_suggestion(data.suggestion)
        end
      end
    end)
  end)
end
