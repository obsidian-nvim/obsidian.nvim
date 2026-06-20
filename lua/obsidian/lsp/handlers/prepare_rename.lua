local api = require "obsidian.api"
local util = require "obsidian.util"

---@param _ lsp.PrepareRenameParams
return function(_, handler)
  local link = api.cursor_link()
  local placeholder
  if link then
    local loc = util.parse_link(link)
    assert(loc, "wrong link format")
    local stripped = util.strip_anchor_links(loc)
    stripped = util.strip_block_links(stripped)
    placeholder = stripped ~= "" and stripped or loc
  else
    local note = api.current_note(0)
    assert(note, "not in a obsidian note")
    placeholder = api.current_note().id
  end

  handler(nil, {
    placeholder = placeholder,
  })
end
