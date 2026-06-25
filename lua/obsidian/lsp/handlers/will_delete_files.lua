local Note = require "obsidian.note"
local Path = require "obsidian.path"

---@param path string
---@param dir string
---@return boolean
local function path_is_in_dir(path, dir)
  path = tostring(Path.new(path))
  dir = tostring(Path.new(dir))
  return path == dir or vim.startswith(path, dir .. "/")
end

---@param abs_path string
local function delete_note(abs_path)
  -- TODO: Handle direct deletion of attachment files by prompting for backlinks
  -- to the attachment and applying the configured trash behavior.
  -- TODO: Handle folder deletion by walking contained notes/attachments and
  -- running the appropriate delete flow for each path.
  if not vim.endswith(abs_path, ".md") then
    return
  end

  local ok, note = pcall(Note.from_file, abs_path)
  if ok and note then
    note:delete { apply = false }
  end
end

---@param params lsp.DeleteFilesParams
---@param callback fun(err: lsp.ResponseError?, result: any)
return function(params, callback)
  if not params or not params.files then
    return callback(nil, {})
  end

  local vault_root = tostring(Obsidian.dir)
  for _, entry in ipairs(params.files) do
    local abs_path = tostring(Path.new(vim.uri_to_fname(entry.uri)))
    if path_is_in_dir(abs_path, vault_root) then
      delete_note(abs_path)
    end
  end

  callback(nil, {})
end
