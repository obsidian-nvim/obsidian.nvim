local api = require "obsidian.api"
local util = require "obsidian.util"

---@param _ lsp.PrepareRenameParams
return function(_, handler)
  local link = api.cursor_link()
  local placeholder
  if link then
    local loc = util.parse_link(link)
    assert(loc, "wrong link format")
    loc = util.strip_anchor_links(loc)
    loc = util.strip_block_links(loc)
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
