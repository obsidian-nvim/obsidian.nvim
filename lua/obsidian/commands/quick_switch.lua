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
      local note = search.resolve_note(entry)[1]
      if not note then
        return log.err("No notes matching '%s'", data.args)
      end
      note:open()
    end,
  }
end
