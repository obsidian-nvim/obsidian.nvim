local Note = require "obsidian.note"
local Path = require "obsidian.path"

---@param abs_path string
local function delete_note(abs_path)
  -- TODO: Handle direct deletion of attachment files by prompting for backlinks.
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

  for _, entry in ipairs(params.files) do
    local abs_path = tostring(Path.new(vim.uri_to_fname(entry.uri)))
    delete_note(abs_path)
  end

  callback(nil, {})
end
