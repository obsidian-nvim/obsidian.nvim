local obsidian_client = require("obsidian").get_client()

return function(_, params, handler, _)
  --- TODO: more precise sense of node under cursor
  --- TODO: hover on tags?
  --- TODO: not work on frontmatter?
  local note_name = vim.fn.expand "<cfile>"
  obsidian_client:find_notes_async(
    note_name,
    vim.schedule_wrap(function(notes)
      for i, note in ipairs(notes) do
        if vim.uri_from_fname(note.path.filename) == params.textDocument.uri then
          table.remove(notes, i)
        end
      end
      local note = notes[1]
      if note then
        local content = table.concat(vim.fn.readfile(note.path.filename), "\n")
        handler(nil, { contents = content })
      else
        vim.notify("No notes found", 3)
      end
    end)
  )
end
