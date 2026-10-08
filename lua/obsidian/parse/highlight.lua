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
    local start_col = line:find("==", search_start, true)
    if not start_col then
      break
    end

    local text_start = start_col + 2
    local close_start = line:find("==", text_start, true)
    if not close_start then
      break
    end

    -- A delimiter pair always belongs to the nearest candidate. This both
    -- keeps adjacent highlights separate and prevents an invalid pair from
    -- swallowing a later valid one.
    local text = line:sub(text_start, close_start - 1)
    if text ~= "" and not text:sub(1, 1):match "%s" and not text:sub(-1):match "%s" then
      local color
      for emoji, emoji_color in pairs(colors) do
        if vim.startswith(text, emoji) then
          color = emoji_color
          text = text:sub(#emoji + 1)
          break
        end
      end

      local end_col = close_start + 1
      matches[#matches + 1] = {
        kind = "highlight",
        raw = line:sub(start_col, end_col),
        range = Range.new(row, start_col - 1, row, end_col),
        text = text,
        color = color,
      }
    end

    search_start = close_start + 2
  end

  return matches
end

return M
