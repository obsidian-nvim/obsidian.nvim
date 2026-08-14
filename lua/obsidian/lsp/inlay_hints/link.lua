local Range = require "obsidian.range"

---@param range lsp.Range|?
---@param position lsp.Position
---@return boolean
local function position_in_range(range, position)
  if not range then
    return true
  end
  local starts_before = range.start.line < position.line
    or (range.start.line == position.line and range.start.character <= position.character)
  local ends_after = range["end"].line > position.line
    or (range["end"].line == position.line and position.character < range["end"].character)
  return starts_before and ends_after
end

---@param value string
---@param position lsp.Position
---@param suggestion obsidian.LinkSuggestion
---@return lsp.InlayHint
local function link_suggestion_hint(value, position, suggestion)
  ---@type lsp.Command
  local command = {
    title = "Apply link suggestion",
    command = "obsidian.link_suggestion",
    arguments = {
      suggestion --[[@as lsp.LSPAny]],
    },
  }
  ---@type lsp.InlayHintLabelPart[]
  local label = {
    {
      value = value,
      command = command,
    },
  }
  return {
    position = position,
    label = label,
    paddingLeft = false,
    paddingRight = false,
    data = { range = Range.to_lsp(suggestion.range) },
  }
end

---@param hints lsp.InlayHint[]
---@param suggestion obsidian.LinkSuggestion
---@param requested_range lsp.Range|?
local function add_link_suggestion_hints(hints, suggestion, requested_range)
  local range = suggestion.range
  if range.start_row ~= range.end_row then
    return
  end

  local start_position = { line = range.start_row, character = range.start_col }
  local end_position = { line = range.end_row, character = range.end_col }
  if position_in_range(requested_range, start_position) then
    hints[#hints + 1] = link_suggestion_hint("[[", start_position, suggestion)
  end
  if position_in_range(requested_range, end_position) then
    hints[#hints + 1] = link_suggestion_hint("]]", end_position, suggestion)
  end
end

---@param note obsidian.Note
---@param range lsp.Range|?
---@return lsp.InlayHint[]
local function get_hints(note, range)
  if not note.path then
    return {}
  end

  local suggestions = note:link_suggestions {
    range = range and Range.lsp(range) or nil,
  }
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

    if not seen_suggestion_ranges[key] then
      add_link_suggestion_hints(hints, suggestion, range)
      seen_suggestion_ranges[key] = true
    end
  end

  return hints
end

return get_hints
