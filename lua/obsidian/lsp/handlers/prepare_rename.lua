local api = require "obsidian.api"

---@param client obsidian.Client
return function(client, _, handler)
  local link = api.parse_cursor_link()
  local placeholder
  if link then
    placeholder = link
  else
    placeholder = client:current_note().id
  end

  handler(nil, {
    placeholder = placeholder,
  })
end
