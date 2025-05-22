local uv = vim.uv

local M = {}

---Gets the notes from the vault recursivly
---@param path string Path to a subfolder of the vault.
---@param files string[]|? Founded pathes to notes.
---@return string[]
local function list_notes_recursive(path, files)
  files = files or {}
  local req = uv.fs_scandir(path)
  if not req then return files end

  while true do
    local name, type = uv.fs_scandir_next(req)
    if not name then break end
    if name ~= "." and name ~= ".." then
      local full_path = path .. "/" .. name
      if type == "directory" then
        list_notes_recursive(full_path, files)
      elseif type == "file" and full_path:sub(#full_path - 2, #full_path) == ".md" then
        table.insert(files, full_path)
      end
    end
  end

  return files
end

---Gets all notes from the vault.
---@param path string The path to the vault.
---@return string[] The path to the notes.
M.get_all_notes_from_vault = function(path)
  return list_notes_recursive(path)
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
