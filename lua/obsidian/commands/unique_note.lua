local Note = require "obsidian.note"
local util = require "obsidian.util"

return function()
  ---@diagnostic disable-next-line: param-type-mismatch
  local date_id = util.format_date(os.time(), Obsidian.opts.unique_note.format)

  local note = Note.create {
    id = date_id,
    template = Obsidian.opts.unique_note.template,
    dir = Obsidian.opts.unique_note.folder,
    should_write = true,
  }

  note:open { sync = true }
end
