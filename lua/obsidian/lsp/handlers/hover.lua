local util = require "obsidian.util"
local search = require "obsidian.search"

--- TODO: tag hover should also work on frontmatter

---@param _ lsp.HoverParams
---@param handler fun(_: any, result: lsp.Hover)
return function(_, handler, _)
  local cursor_ref = util.cursor_link()
  local cursor_tag = util.cursor_tag()
  if cursor_ref then
    local title = util.parse_link(cursor_ref, { strip = true })
    if not title then
      return
    end
    local notes = search.resolve_note(title, {})
    if vim.tbl_isempty(notes) then
      return
    end
    -- local contents = Obsidian.opts.lsp.hover.note_preview_callback(note)
    local contents = notes[1]:display_info()
    handler(nil, { contents = contents })
  elseif cursor_tag then
    local tag_locs = search.find_tags(cursor_tag, {})

    local notes_lookup = {}
    for _, tag_loc in ipairs(tag_locs) do
      notes_lookup[tostring(tag_loc.note.path)] = true
    end

    local note_count = vim.tbl_count(notes_lookup)
    local contents = string.format("**found in %s notes**", note_count)

    handler(nil, { contents = contents })
  else
    vim.notify("No note or tag found", 3)
  end
end
