local obsidian = require "obsidian"

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
    local rge = {
      start = { line = anchor.line - 1, character = 0 },
      ["end"] = { line = anchor.line - 1, character = 0 },
    }
    if not lookup[anchor.line] then
      local symbol = {
        name = display,
        kind = 1,
        filename = note.path.filename,
        range = rge,
        selectionRange = rge,
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
