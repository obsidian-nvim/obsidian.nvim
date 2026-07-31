local api = require "obsidian.api"
local Range = require "obsidian.range"

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

---@param value string
---@param position lsp.Position
---@param range lsp.Range
---@return lsp.InlayHint
local function link_suggestion_hint(value, position, range)
  return {
    position = position,
    label = {
      {
        value = value,
        command = {
          title = "Apply link suggestion",
          command = "obsidian.link_suggestion",
        },
      },
    },
    paddingLeft = false,
    paddingRight = false,
    data = { range = range },
  }
end

---@param hints lsp.InlayHint[]
---@param suggestion obsidian.LinkSuggestion
local function add_link_suggestion_hints(hints, suggestion)
  local range = suggestion.range
  if range.start_row ~= range.end_row then
    return
  end

  local lsp_range = Range.to_lsp(range)
  hints[#hints + 1] = link_suggestion_hint("[[", { line = range.start_row, character = range.start_col }, lsp_range)
  hints[#hints + 1] = link_suggestion_hint("]]", { line = range.end_row, character = range.end_col }, lsp_range)
end

---@param bufnr integer
---@param range lsp.Range|?
---@return lsp.InlayHint[]
local function get_hints(bufnr, range)
  local note = api.current_note(bufnr)
  if not note then
    return {}
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local suggestions = note:link_suggestions {
    current_path = bufname,
    dir = api.resolve_workspace_dir(bufname),
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

    if line_in_range(range, suggestion_range.start_row) and not seen_suggestion_ranges[key] then
      add_link_suggestion_hints(hints, suggestion)
      seen_suggestion_ranges[key] = true
    end
  end

  return hints
end

return get_hints
