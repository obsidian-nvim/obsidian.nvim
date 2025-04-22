-- stealing from telekasten
return {
  calendar_action = function(day, month, year, _, _)
    local client = require("obsidian").get_client()
    local datetime = os.time { year = year, month = month, day = day }
    local daily_note_path = client:daily_note_path(datetime)

    vim.cmd.quit()
    Notes = require "obsidian.note"
    client:open_note(daily_note_path)
    vim.schedule(function()
      vim.cmd "CalendarVR"
      vim.cmd "wincmd h"
    end)
  end,
}
