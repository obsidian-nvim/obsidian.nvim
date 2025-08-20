local RefTypes = require("obsidian.search").RefTypes
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param params lsp.ReferenceParams
---@param handler fun(_:any, loactions: lsp.Location[])
return function(params, handler)
  local cur_link, link_type = api.cursor_link()
  if not cur_link then
    return
  end

  local link_match = search.resolve_link(cur_link, {})
  if not link_match then
    return
  end

  if link_type ~= RefTypes.NakedUrl and link_type ~= RefTypes.FileUrl and link_type ~= RefTypes.BlockID then
    local line = link_match.line and link_match.line - 1 or 0
    local uri = vim.uri_from_fname(tostring(link_match.path))

    handler(nil, {
      uri = uri,
      range = uri and {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    })
  elseif link_type == RefTypes.FileUrl then
    if not link_match.location then
      return
    end
    local path = link_match.location:sub(6)

    handler(nil, {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
    })
  end
end
