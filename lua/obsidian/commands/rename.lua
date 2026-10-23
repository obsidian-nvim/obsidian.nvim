local api = require("obsidian").api
local log = require("obsidian").log

--- Rename the note of the current buffer, whatever is under the cursor.
--- (`vim.lsp.buf.rename` renames the element under the cursor instead.)
---@param data obsidian.CommandArgs
return function(data)
  local note = api.current_note(0)
  if not note then
    return log.err "Current buffer is not a note inside the vault"
  end

  local new_name = vim.trim(data.args or "")
  if new_name == "" then
    new_name = api.input("New name", { default = note.id }) or ""
  end
  if new_name == "" then
    return log.warn "Aborted"
  end

  -- Same as the LSP handler: ripgrep must see the saved contents.
  local ok, err = pcall(vim.cmd.wall)
  if not ok then
    return log.err(err or "failed writing all buffers before renaming, abort")
  end

  -- The no-op callback makes name collisions log instead of raising.
  note:rename(new_name, {}, function() end)
end
