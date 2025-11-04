local obsidian = require "obsidian"

return function()
  local note = assert(obsidian.api.current_note(0))

  local key = obsidian.api.input "key: "
  local value = obsidian.api.input "value: "

  if not (key and value) then
    return obsidian.log "Aborted"
  end

  if vim.trim(key) ~= "" and vim.trim(value) ~= "" then
    return obsidian.log "Empty Input"
  end

  note:add_field(key, value)
  note:update_frontmatter(0)
end
