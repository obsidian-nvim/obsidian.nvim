local search = require "obsidian.search"

-- TODO: search in current text edit?
-- TODO: only enable in 0.12+
-- TODO: highlight hex colors?

---@param color integer
---@return lsp.Color
local function int_to_rgb(color)
  local r = bit.rshift(color, 16) % 256
  local g = bit.rshift(color, 8) % 256
  local b = color % 256

  return {
    red = r / 255,
    green = g / 255,
    blue = b / 255,
    alpha = 1,
  }
end

local function get_markup_link_color()
  local hl = vim.api.nvim_get_hl(0, { name = "@markup.link.label" })
  return int_to_rgb(hl.bg or 15961000)
end

local function gen_color_info(line, st, ed)
  return {
    range = {
      start = { line = line, character = st },
      ["end"] = { line = line, character = ed },
    },
    color = get_markup_link_color(),
  }
end

return function(_, handler)
  ---@type lsp.ColorInformation[]
  local result = {}

  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local matches = search.find_tags_in_string(line)
    if not vim.tbl_isempty(matches) then
      for _, match in ipairs(matches) do
        result[#result + 1] = gen_color_info(lnum - 1, match[1] - 1, match[2])
      end
    end
  end

  handler(nil, result)
end
