local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param data obsidian.CommandArgs
return function(data)
  local query

  if data.args and data.args ~= "" then
    query = data.args
  end

  -- TODO: clean logic
  if query then
    local notes = search.resolve_note(query)

    if vim.tbl_isempty(notes) then
      return log.info "Failed to Switch" -- TODO:
    elseif #notes == 1 then
      local note = notes[1]
      return api.open_buffer(note.path)
    end
  else
    Obsidian.picker:find_notes {
      prompt_title = "Quick Switch",
      query = query,
      use_cache = Obsidian.opts.cache.enabled,
    }
  end
end
