local log = require "obsidian.log"

return function(client, data)
  local function rename(new_note_id)
    if new_note_id == "" then
      log.err "Invalid new note ID"
      return
    elseif vim.endswith(new_note_id, ".md") then
      new_note_id = string.sub(new_note_id, 1, -4)
    end
    vim.lsp.buf.rename(new_note_id, { name = "obsidian-ls" })
  end
end
