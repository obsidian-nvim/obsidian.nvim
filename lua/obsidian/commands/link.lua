local search = require "obsidian.search"
local api = require "obsidian.api"
local log = require "obsidian.log"

---@param data obsidian.CommandArgs
return function(data)
  local viz = api.get_visual_selection()
  if not viz then
    log.err "`Obsidian link` must be called with visual selection"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  local line = assert(viz.lines[1], "invalid visual selection")

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
      .. note:format_link { label = viz.selection }
      .. string.sub(line, viz.cecol + 1)
    vim.api.nvim_buf_set_lines(0, viz.csrow - 1, viz.csrow, false, { new_line })
    require("obsidian.ui").update(0)
  end

  local picker = Obsidian.picker

  if not picker then
    log.err "No picker configured"
    return
  end

  picker:find_notes {
    prompt_title = "Select note to link",
    query = query,
    callback = function(entry)
      local resolved_notes = search.resolve_note(entry)
      if #resolved_notes == 0 then
        return log.err("No notes matching '%s'", entry)
      end
      local note = resolved_notes[1]
      vim.schedule(function()
        insert_ref(note)
      end)
    end,
  }
end
