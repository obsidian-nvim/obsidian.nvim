local api = require "obsidian.api"
local log = require "obsidian.log"
local Note = require "obsidian.note"

---@param data obsidian.CommandArgs
return function(data)
  ---@type obsidian.Note
  local note, id
  if data.args:len() > 0 then
    id = data.args
  else
    id = api.input("Enter id or path (optional): ", { completion = "file" })
    if not id then
      return log.warn "Aborted"
    elseif id == "" then
      id = nil
    end
  end

  note = Note.create {
    id = id,
    template = Obsidian.opts.note.template, -- TODO: maybe unneed when creating, or set as a field that note carries
  }

  -- Open the note in a new buffer.
  note:open { sync = true }
  note:write_to_buffer {
    template = Obsidian.opts.note.template,
  }
end
