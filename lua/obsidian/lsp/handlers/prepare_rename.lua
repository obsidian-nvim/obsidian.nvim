local api = require "obsidian.api"

---@param _ lsp.PrepareRenameParams
return function(_, handler)
  local link = api.parse_cursor_link()
  local placeholder
  if link then
    placeholder = link
  else
    placeholder = api.current_note().id
  end

  handler(nil, {
    placeholder = placeholder,
  })
end
