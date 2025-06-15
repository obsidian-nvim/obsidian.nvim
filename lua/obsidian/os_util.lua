local log = require "obsidian.log"

local M = {}

---Gets all notes from the vault.
---@param path string The path to the vault.
---@return string[]|? The path to the notes.
M.get_all_notes_from_vault = function(path)
  local handle = io.popen("fd -t file -a --base-directory " .. path)
  if not handle then
    log.err "Failed to execute command"
    return nil
  end

  local files = {}

  for file in handle:lines() do
    table.insert(files, file)
  end

  handle:close()

  return files
end

---Gets all subfolders from the vault.
---@param path string The path to the vault.
---@return string[] The path to the subfolders
M.get_sub_dirs_from_vault = function(path)
  local handle = io.popen("fd -t directory -a --base-directory " .. path)
  if not handle then
    error "Failed to execute command"
  end

  local subdirs = {}

  for dir in handle:lines() do
    table.insert(subdirs, dir)
  end

  handle:close()

  return subdirs
end

return M
