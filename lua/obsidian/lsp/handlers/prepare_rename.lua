local api = require "obsidian.api"
local util = require "obsidian.util"

---@param _ lsp.PrepareRenameParams
return function(_, handler)
  local link = api.cursor_link()
  local placeholder
  if link then
    local loc = util.parse_link(link, { strip = true })
    assert(loc, "wrong link format")
    placeholder = loc
  else
    local note = api.current_note(0)
    assert(note, "not in a obsidian note")
    placeholder = api.current_note().id
  end

  handler(nil, {
    placeholder = placeholder,
  })
end
