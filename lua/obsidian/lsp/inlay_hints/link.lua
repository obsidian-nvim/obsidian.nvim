local Range = require "obsidian.range"
local link_suggestion = require "obsidian.link_suggestion"

-- TODO: extract to range class?
---@param range lsp.Range|?
---@param line_nr integer
---@return boolean
local function line_in_range(range, line_nr)
  if not range then
    return true
  end
  return range.start.line <= line_nr and line_nr <= range["end"].line
end

---@param suggestion obsidian.LinkSuggestion
---@return lsp.TextEdit[]
local function text_edits_for_suggestion(suggestion)
  return {
    {
      range = Range.to_lsp(suggestion.range),
      newText = suggestion.new_text,
    },
  }
end

---@param hints lsp.InlayHint[]
---@param suggestion obsidian.LinkSuggestion
local function add_link_suggestion_hints(hints, suggestion)
  local range = suggestion.range
  if range.start_row ~= range.end_row then
    return
  end

  local text_edits = text_edits_for_suggestion(suggestion)
  hints[#hints + 1] = {
    position = { line = range.start_row, character = range.start_col },
    label = "[[",
    paddingLeft = false,
    paddingRight = false,
    textEdits = text_edits,
  }
  hints[#hints + 1] = {
    position = { line = range.end_row, character = range.end_col },
    label = "]]",
    paddingLeft = false,
    paddingRight = false,
    textEdits = text_edits,
  }
end

---@param bufnr integer
---@param range lsp.Range|?
---@return lsp.InlayHint[]
local function get_hints(bufnr, range)
  local suggestions = link_suggestion.find_buffer(bufnr)
  local seen_suggestion_ranges = {}

  ---@type lsp.InlayHint[]
  local hints = {}

  for _, suggestion in ipairs(suggestions) do
    local suggestion_range = suggestion.range
    local key = string.format(
      "%d:%d:%d:%d",
      suggestion_range.start_row,
      suggestion_range.start_col,
      suggestion_range.end_row,
      suggestion_range.end_col
    )

    if line_in_range(range, suggestion_range.start_row) and not seen_suggestion_ranges[key] then
      add_link_suggestion_hints(hints, suggestion)
      seen_suggestion_ranges[key] = true
    end
  end

  return hints
end

return get_hints
