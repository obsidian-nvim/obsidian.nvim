local api = require "obsidian.api"

---@param _ lsp.DocumentSymbolParams
return function(_, handler)
  local note = assert(api.current_note(0, { collect_anchor_links = true }))

  ---@type lsp.DocumentSymbol[]
  local symbols = {}
  for _, anchor in pairs(note.anchor_links) do
    local display = string.rep("#", anchor.level) .. " " .. anchor.header
    local rge = {
      start = { line = anchor.line - 1, character = 0 },
      ["end"] = { line = anchor.line - 1, character = 0 },
    }
    symbols[#symbols + 1] = {
      name = display,
      kind = 1,
      filename = note.path.filename,
      range = rge,
      selectionRange = rge,
    }
  end

  table.sort(symbols, function(a, b)
    return a.range.start.line < b.range.start.line
  end)

  handler(nil, symbols)
end
