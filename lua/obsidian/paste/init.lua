local attachments = require "obsidian.paste.attachment"
local html = require "obsidian.paste.html"

-- TOOD: overridable handler for attachment and html

return {
  put = function(lines, mode, after, follow_cursor)
    local attachment_type = attachments.get_attachment_type()
    if attachment_type then
      lines = attachments.get(nil, attachment_type)
      mode = vim.F.if_nil(mode, "c")
      after = vim.F.if_nil(after, true)
      follow_cursor = vim.F.if_nil(follow_cursor, false)
    elseif html.has() then
      lines = html.get()
      mode = vim.F.if_nil(mode, "b")
      after = vim.F.if_nil(after, true)
      follow_cursor = vim.F.if_nil(follow_cursor, true)
    end
    vim.api.nvim_put(lines, mode, after, follow_cursor)
  end,
}
