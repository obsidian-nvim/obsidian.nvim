local api = require "obsidian.api"
local log = require "obsidian.log"
local Note = require "obsidian.note"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  ---@type obsidian.Note
  local note
  if data.args:len() > 0 then
    note = Note.create { title = data.args }
  else
    local title = api.input("Enter title or path (optional): ", { completion = "file" })
    if not title then
      log.warn "Aborted"
      return
    elseif title == "" then
      title = nil
    end
    note = Note.create { title = title }
  end

  -- Open the note in a new buffer.
  client:open_note(note, { sync = true })
  note:write_to_buffer()
end
