--- Handle the "search" action.
---@param parsed obsidian.uri.Parsed
local function handle_search(parsed)
  Obsidian.picker.grep_notes {
    query = parsed.query,
  }
end

return handle_search
