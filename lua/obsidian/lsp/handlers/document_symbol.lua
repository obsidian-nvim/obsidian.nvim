local obsidian = require "obsidian"
local Range = require "obsidian.range"

---@param _ lsp.DocumentSymbolParams
return function(_, handler)
  ---@type lsp.DocumentSymbol[]
  local symbols = {}
  local lookup = {}

  local note = obsidian.Note.from_buffer(0, { collect_anchor_links = true })
  if not note then -- HACK: somehow DocumentSymbol gets called with no valid note
    return handler(nil, symbols)
  end

  for _, anchor in pairs(note.anchor_links) do
    local display = string.rep("#", anchor.level) .. " " .. anchor.header
    if not lookup[anchor.line] then
      local symbol = {
        name = display,
        kind = 1,
        filename = note.path.filename,
        range = Range.to_lsp(anchor.section.range),
        selectionRange = Range.to_lsp(anchor.section.heading_range),
      }
      symbols[#symbols + 1] = symbol
      lookup[anchor.line] = true
    end
  end

  table.sort(symbols, function(a, b)
    return a.range.start.line < b.range.start.line
  end)

  handler(nil, symbols)
end
