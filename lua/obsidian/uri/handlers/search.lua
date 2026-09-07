local ut = require "obsidian.uri.util"

--- Handle the `search` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_search(parsed)
  Obsidian.picker.grep_notes { query = parsed.query }
  return ut.success(parsed, { interactive = true })
end

return handle_search
