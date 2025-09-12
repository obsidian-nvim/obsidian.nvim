local log = require "obsidian.log"
local api = require "obsidian.api"
local Note = require "obsidian.note"

---Extract the selected text into a new note
---and replace the selection with a link to the new note.
---
---@param data CommandArgs
return function(data)
  local viz = api.get_visual_selection()
  if not viz then
    log.err "Obsidian extract_note must be called with visual selection"
    return
  end

  local content = vim.split(viz.selection, "\n", { plain = true })

  ---@type string|?
  local title
  if data.args ~= nil and string.len(data.args) > 0 then
    title = vim.trim(data.args)
  else
    title = api.input "Enter title (optional): "
    if not title then
      log.warn "Aborted"
      return
    elseif title == "" then
      title = nil
    end
  end

  -- create the new note.
  local note = Note.create { title = title }

  -- replace selection with link to new note
  local link = api.format_link(note)
  vim.api.nvim_buf_set_text(0, viz.csrow - 1, viz.cscol - 1, viz.cerow - 1, viz.cecol, { link })

  require("obsidian.ui").update(0)

  -- add the selected text to the end of the new note
  note:open { sync = true }
  vim.api.nvim_buf_set_lines(0, -1, -1, false, content)
end
