local Range = require "obsidian.range"

local M = {}

---@alias obsidian.parse.HighlightColor "red"|"orange"|"yellow"|"green"|"blue"|"purple"

---@class obsidian.parse.Highlight : obsidian.parse.line.Match
---@field kind "highlight"
---@field text string Highlight text without the delimiters or color emoji.
---@field color obsidian.parse.HighlightColor? Color selected by a leading emoji.

local colors = {
  ["🔴"] = "red",
  ["🟠"] = "orange",
  ["🟡"] = "yellow",
  ["🟢"] = "green",
  ["🔵"] = "blue",
  ["🟣"] = "purple",
}

---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.Highlight[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local matches = {}
  local search_start = 1
  while search_start < #line do
    local start_col, end_col = line:find("==[^=]+==", search_start)
    if not start_col or not end_col then
      break
    end

    local text = line:sub(start_col + 2, end_col - 2)
    if vim.trim(text) == text then
      local color
      for emoji, emoji_color in pairs(colors) do
        if vim.startswith(text, emoji) then
          color = emoji_color
          text = text:sub(#emoji + 1)
          break
        end
      end

      matches[#matches + 1] = {
        kind = "highlight",
        raw = line:sub(start_col, end_col),
        range = Range.new(row, start_col - 1, row, end_col),
        text = text,
        color = color,
      }
    end

    search_start = end_col
  end

  return matches
end

-- `parse` is kept as a convenient singular parser name for callers that use
-- the parse namespace; highlights may occur more than once on a line.
M.parse = M.extract

return M
