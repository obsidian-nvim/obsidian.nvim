local util = require "obsidian.util"
local search = require "obsidian.search"

--- TODO: tag hover should also work on frontmatter

---@param _ lsp.HoverParams
---@param handler function
return function(_, handler, _)
  local cursor_ref = util.cursor_link()
  local cursor_tag = util.cursor_tag()
  if cursor_ref then
    local title = util.parse_link(cursor_ref, { strip = true })
    if not title then
      return
    end
    local note = search.resolve_note(title, {})
    if not note then
      return
    end
    local contents = Obsidian.opts.lsp.hover.note_preview_callback(note)
    handler(nil, {
      contents = contents,
    })
  elseif cursor_tag then
    -- lsp_util.preview_tag(client, params, cursor_tag, function(content)
    --   if content then
    --     handler(nil, {
    --       contents = content,
    --     })
    --   else
    --     vim.notify("No tag found", 3)
    --   end
    -- end)
  else
    vim.notify("No note or tag found", 3)
  end
end
