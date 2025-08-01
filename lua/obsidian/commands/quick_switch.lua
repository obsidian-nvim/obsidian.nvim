local log = require "obsidian.log"
local search = require "obsidian.search"

---@param data CommandArgs
return function(_, data)
  if not data.args or string.len(data.args) == 0 then
    local picker = Obsidian.picker
    if not picker then
      log.err "No picker configured"
      return
    end

    picker:find_notes { use_cache = Obsidian.opts.cache.enabled }
  else
    search.resolve_note_async(data.args, function(note)
      if not note then
        return log.err("No notes matching '%s'", data.args)
      end
      note:open()
    end)
  end
end
