local log = require "obsidian.log"
local search = require "obsidian.search"

---@param data obsidian.CommandArgs
return function(data)
  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  picker:find_notes {
    prompt_title = "Quick Switch",
    query = data.args,
    callback = function(entry)
      local resolved_notes = search.resolve_note(entry)
      if #resolved_notes == 0 then
        return log.err("No notes matching '%s'", entry)
      end
      local note = resolved_notes[1]
      note:open()
    end,
  }
end
