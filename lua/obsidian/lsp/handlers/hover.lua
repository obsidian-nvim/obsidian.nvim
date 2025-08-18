local util = require "obsidian.util"
local search = require "obsidian.search"

--- TODO: tag hover should also work on frontmatter

---@param params lsp.HoverParams
---@param handler function
return function(params, handler, _)
  local cursor_ref = util.cursor_link()
  local cursor_tag = util.cursor_tag()
  if cursor_ref then
    local title = util.parse_link(cursor_ref)
    title = title and util.strip_anchor_links(title)
    title = title and util.strip_block_links(title)
    if not title then
      return
    end
    local note = search.resolve_note(title, {})
    if not note then
      return
    end
    note:load_contents()
    handler(nil, {
      contents = note.contents,
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
