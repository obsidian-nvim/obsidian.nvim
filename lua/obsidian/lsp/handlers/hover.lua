local util = require "obsidian.util"
local lsp_util = require "obsidian.lsp.util"

--- TODO: tag hover should also work on frontmatter

---@param client obsidian.Client
---@param params table
---@param handler function
return function(client, params, handler, _)
  local cursor_ref = util.parse_cursor_link() -- TODO: use title to validate if note is right
  local cursor_tag = util.cursor_tag()
  if cursor_ref then
    lsp_util.preview_ref(client, params, cursor_ref, function(content)
      if content then
        handler(nil, {
          contents = content,
        })
        vim.notify("No note found", 3)
      end
    end)
  elseif cursor_tag then
    lsp_util.preview_tag(client, params, cursor_tag, function(content)
      if content then
        handler(nil, {
          contents = content,
        })
      else
        vim.notify("No tag found", 3)
      end
    end)
  else
    vim.notify("No note or tag found", 3)
  end
end
