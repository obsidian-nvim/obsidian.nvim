local obsidian = require "obsidian"
local Range = require "obsidian.range"

---@param _ lsp.DocumentSymbolParams
return function(_, handler)
  ---@type lsp.DocumentSymbol[]
  local symbols = {}

  local note = obsidian.Note.from_buffer(0, { collect_sections = true })
  if not note then -- HACK: somehow DocumentSymbol gets called with no valid note
    return handler(nil, symbols)
  end

  for _, section in ipairs(note.sections or {}) do
    if section.header then
      symbols[#symbols + 1] = {
        name = string.rep("#", section.level) .. " " .. section.header,
        kind = 1,
        filename = note.path.filename,
        range = Range.to_lsp(section.range),
        selectionRange = Range.to_lsp(section.heading_range),
      }
    end
  end

  handler(nil, symbols)
end
