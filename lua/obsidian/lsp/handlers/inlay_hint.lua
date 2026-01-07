local obsidian = require "obsidian"

---@type table<obsidian.search.RefTypes, function>
local handlers = {}

handlers.Wiki = function(match)
  local location = obsidian.util.parse_link(match.link)
  if not location then
    return
  end

  location = location:gsub(".md", "") -- TODO:

  local notes = obsidian.search.resolve_note(location)
  if #notes == 0 then
    return
  end
  local num_backlinks = #notes[1]:backlinks {}
  if num_backlinks == 0 then
    return
  end
  return num_backlinks .. " refs" -- TODO: further extract backlink provider
end

handlers.WikiWithAlias = handlers.Wiki
handlers.Markdown = handlers.Wiki

---@return lsp.InlayHint[]|?
local function get_hints()
  local note = obsidian.api.current_note(0)
  if not note then
    return
  end
  local links = note:links()

  ---@type lsp.InlayHint[]
  local hints = {}

  for _, link_match in ipairs(links) do
    if handlers[link_match.type] then
      local label = handlers[link_match.type](link_match)
      if label then
        hints[#hints + 1] = {
          position = { line = link_match.line - 1, character = link_match["end"] + 1 },
          label = label,
          paddingLeft = true,
          paddingRight = true,
        }
      end
    end
  end

  return hints
end

---@param callback fun(_: any, hints: lsp.InlayHint[]|?)
return function(_, callback)
  local hints = get_hints()
  callback(nil, hints)
end
