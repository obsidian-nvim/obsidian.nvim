local api = require "obsidian.api"
local refs = require "obsidian.parse.refs"
local link_parser = require "obsidian.link.parser"

---@param _ lsp.PrepareRenameParams
return function(_, handler)
  local link = api.cursor_link()
  local placeholder
  if link then
    local ref = assert(refs.parse(link), "wrong link format")
    placeholder = ref.target ~= "" and ref.target or link_parser.format(ref.target, ref.anchor, ref.block)
  else
    local note = api.current_note(0)
    assert(note, "not in a obsidian note")
    placeholder = note.id
  end

  handler(nil, {
    placeholder = placeholder,
  })
end
