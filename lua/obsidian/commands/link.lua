local search = require "obsidian.search"
local api = require "obsidian.api"
local log = require "obsidian.log"

---@param data CommandArgs
return function(_, data)
  local viz = api.get_visual_selection()
  if not viz then
    log.err "`Obsidian link` must be called with visual selection"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  local line = assert(viz.lines[1])

  ---@type string
  local query
  if data.args ~= nil and string.len(data.args) > 0 then
    query = data.args
  else
    query = viz.selection
  end

  ---@param note obsidian.Note
  local function insert_ref(note)
    local new_line = string.sub(line, 1, viz.cscol - 1)
      .. api.format_link(note, { label = viz.selection })
      .. string.sub(line, viz.cecol + 1)
    vim.api.nvim_buf_set_lines(0, viz.csrow - 1, viz.csrow, false, { new_line })
    require("obsidian.ui").update(0)
  end

  search.resolve_note_async(query, function(note)
    if not note then
      return log.err("No notes matching '%s'", query)
    end
    vim.schedule(function()
      insert_ref(note)
    end)
  end, { prompt_title = "Select note to link" })
end
