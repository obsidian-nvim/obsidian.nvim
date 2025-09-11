local RefTypes = require("obsidian.search").RefTypes
local api = require "obsidian.api"
local search = require "obsidian.search"
local Note = require "obsidian.note"

-- TODO:merge first and iterate, eventually replace `api.follow_link`

local IsNote = {
  [RefTypes.WikiWithAlias] = true,
  [RefTypes.Wiki] = true,
  [RefTypes.Markdown] = true,
}

local IsWiki = {
  [RefTypes.WikiWithAlias] = true,
  [RefTypes.Wiki] = true,
}

---@param params lsp.ReferenceParams
---@param handler fun(_:any, loactions: lsp.Location[])
return function(params, handler)
  local cur_link, link_type = api.cursor_link()
  if not cur_link then
    return
  end

  local match = search.resolve_link(cur_link, {})
  if not match then
    return
  end

  if IsNote[link_type] then
    if match.note then
      local line = match.line and match.line - 1 or 0
      local uri = vim.uri_from_fname(tostring(match.path))

      handler(nil, {
        uri = uri,
        range = uri and {
          start = { line = line, character = 0 },
          ["end"] = { line = line, character = 0 },
        },
      })
    elseif IsWiki[link_type] then -- Prompt to create a new note.
      if api.confirm("Create new note '" .. match.location .. "'?") then
        ---@type string|?, string[]
        local id, aliases
        if match.name == match.location then
          aliases = {}
        else
          aliases = { match.name }
          id = match.location
        end

        local note = Note.create { title = match.name, id = id, aliases = aliases }
        note:save()

        handler(nil, {
          uri = vim.uri_from_fname(note.path.filename),
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 0 },
          },
        })
      end
    end
  elseif link_type == RefTypes.FileUrl then
    if not match.location then
      return
    end
    local path = match.location:sub(6)

    handler(nil, {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
    })
  end
end
