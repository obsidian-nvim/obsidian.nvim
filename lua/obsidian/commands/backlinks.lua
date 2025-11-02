local obsidian = require "obsidian"

return function()
  local picker = Obsidian.picker

  vim.lsp.buf.references(nil, {
    on_list = (not picker.state._native) and function(t)
      picker.pick(t.items, {
        prompt_title = "Backlinks",
        callback = function(v)
          obsidian.api.open_buffer(v.filename, { col = v.col, line = v.lnum })
        end,
      })
    end or nil,
  })
end
