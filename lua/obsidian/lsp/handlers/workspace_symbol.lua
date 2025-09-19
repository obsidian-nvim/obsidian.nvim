local search = require "obsidian.search"

---@param params lsp.WorkspaceSymbolParams
---@param handler function
return function(params, handler)
  local query = params.query

  local notes = search.find_notes(query, {})

  ---@type lsp.WorkspaceSymbol[]
  local results = {}

  for _, note in ipairs(notes) do
    results[#results + 1] = {
      name = note:display_name(),
      kind = 1,
      location = {
        uri = vim.uri_from_fname(note.path.filename),
        -- range = {},
      },
    }
  end

  handler(nil, results)
end
