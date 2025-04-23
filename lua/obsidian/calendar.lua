-- adapted from telekasten.nvim: https://github.com/nvim-telekasten/telekasten.nvim
local cmd2nav = {
  CalendarVR = "wincmd h",
  Calendar = "wincmd l",
  CalendarH = "wincmd k",
  CalendarT = "",
}

local M = {}

-- set up calendar integration: forward to our lua functions
M.setup = function(opts)
  for k, v in pairs(opts) do
    vim.g["calendar_" .. k] = v
  end

  vim.cmd [[
  function! ObsidianCalSign(day, month, year)
     return luaeval('require("obsidian.calendar").calendar_sign(_A[1], _A[2], _A[3])', [a:day, a:month, a:year])
  endfunction
  function! ObsidianCalAction(day, month, year, weekday, dir)
     return luaeval('require"obsidian.calendar".calendar_action(_A[1], _A[2], _A[3], _A[4], _A[5])', [a:day, a:month, a:year, a:weekday, a:dir])
  endfunction
  ]]
  vim.g.calendar_sign = "ObsidianCalSign"
  vim.g.calendar_action = "ObsidianCalAction"
  return true
end

-- action called when a date is selected
M.calendar_action = function(day, month, year, _, _)
  local datetime = os.time { year = year, month = month, day = day }
  local client = require("obsidian").get_client()
  local opts = client.opts.calendar
  local daily_note_path = client:daily_note_path(datetime)
  if opts.close_after and opts.cmd ~= "CalendarT" then
    vim.cmd.close()
  else
    local nav_cmd = cmd2nav[opts.cmd]
    vim.cmd(nav_cmd)
  end

  client:open_note(daily_note_path)
end

-- determine if a date has a note attached
M.calendar_sign = function(day, month, year)
  local client = require("obsidian").get_client()
  local datetime = os.time { year = year, month = month, day = day }
  local daily_note_path = client:daily_note_path(datetime)
  if daily_note_path:exists() then
    return 1
  end
  return 0
end

return M
