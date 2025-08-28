local api = require "obsidian.api"
local log = require "obsidian.log"
local Note = require "obsidian.note"

---@param data obsidian.CommandArgs
return function(data)
  ---@type obsidian.Note
  local note
  if data.args:len() > 0 then
    note = Note.create { id = data.args }
  else
    local id = api.input("Enter id or path (optional): ", { completion = "file" })
    if not id then
      return log.warn "Aborted"
    elseif id == "" then
      id = nil
    end
    note = Note.create { id = id }
  end

  -- Open the note in a new buffer.
  note:open { sync = true }
  note:write_to_buffer()
end
