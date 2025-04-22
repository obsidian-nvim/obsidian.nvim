-- set up calendar integration: forward to our lua functions
local function setup_calendar_vim()
  vim.cmd [[
function! MyCalAction(day, month, year, weekday, dir)
   return luaeval('require"obsidian.calendar".calendar_action(_A[1], _A[2], _A[3], _A[4], _A[5])', [a:day, a:month, a:year, a:weekday, a:dir])
endfunction

let g:calendar_action = 'MyCalAction'
" let g:calendar_sign = 'MyCalSign'
" let g:calendar_begin = 'MyCalBegin'
]]
end

setup_calendar_vim()

return function(client)
  vim.cmd "CalendarVR"
end
