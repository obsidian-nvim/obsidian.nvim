-- stealing from telekasten
function _G.calendar_action(day, month, year, _, _)
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
end

local function setup_calendar()
  -- set up calendar integration: forward to our lua functions
  vim.cmd [[
function! MyCalAction(day, month, year, weekday, dir)
   return luaeval('calendar_action(_A[1], _A[2], _A[3], _A[4], _A[5])', [a:day, a:month, a:year, a:weekday, a:dir])
endfunction

let g:calendar_action = 'MyCalAction'
" let g:calendar_sign = 'MyCalSign'
" let g:calendar_begin = 'MyCalBegin'
]]
end

return function(client)
  setup_calendar()
  vim.cmd "CalendarVR"
end
