local M = {}
local uv = vim.uv
local api = require "obsidian.api"

--- Register the global variable that updates itself
M.start = function(client)
  local current_note

  local refresh = function()
    local note = client:current_note()
    if not note then -- no note
      return ""
    elseif current_note == note then -- no refresh
      return
    else -- refresh
      current_note = note
    end

    api.find_backlinks(
      note,
      {},
      vim.schedule_wrap(function(backlinks)
        local format = assert(client.opts.statusline.format)
        local wc = vim.fn.wordcount()
        local info = {
          words = wc.words,
          chars = wc.chars,
          backlinks = #backlinks,
          properties = vim.tbl_count(note:frontmatter()),
        }
        for k, v in pairs(info) do
          format = format:gsub("{{" .. k .. "}}", v)
        end
        vim.g.obsidian = format
      end)
    )
  end

  local timer = uv:new_timer()
  assert(timer, "Failed to create timer")
  timer:start(0, 1000, vim.schedule_wrap(refresh))
end

return M
