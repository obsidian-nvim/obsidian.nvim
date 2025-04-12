local obsidian_client = require("obsidian").get_client()

-- TODO: not working

return function(params, handler, _)
  local buf = vim.api.nvim_get_current_buf()
  local current_uri = vim.uri_from_bufnr(buf)
  obsidian_client:find_notes_async(
    params.label,
    vim.schedule_wrap(function(notes)
      for i, note in ipairs(notes) do
        if vim.uri_from_fname(note.path.filename) == current_uri then
          table.remove(notes, i)
        end
      end
      local note = notes[1]
      if note then
        local content = table.concat(vim.fn.readfile(note.path.filename), "\n")
        handler(nil, {
          value = content,
          kind = "markdown",
        })
      else
        vim.notify("No notes found", 3)
      end
    end)
  )
  --   params.documentation = {
  --     value = [[# Heading 1
  -- [link](https://example.com)
  --      ]],
  --     kind = "markdown",
  --   }
  -- handler(nil, params)
end
