local obsidian = require "obsidian"
local Note = obsidian.Note
local api = obsidian.api
local rename = require "obsidian.lsp.handlers._rename"

---@param file lsp.FileRename
---@param dispatchers table
local function rename_note(file, dispatchers)
  local new_path = vim.uri_to_fname(file.newUri)
  local note = Note.from_file(new_path)
  local new_name = vim.fs.basename(new_path):gsub("%.md$", "")
  local edit = rename.build_edit(note, new_name, {
    old_path = vim.uri_to_fname(file.oldUri),
    new_path = new_path,
    include_file_rename = false,
  })

  if not edit then
    return
  end

  if Obsidian.opts.link.auto_update ~= true then
    local choice = api.confirm(("Update links to renamed note '%s'?"):format(new_name))
    if choice ~= "Yes" then
      return
    end
  end

  dispatchers.server_request("workspace/applyEdit", {
    label = "Update renamed note references",
    edit = edit,
  })
end

---@param params lsp.RenameFilesParams
---@param dispatchers table
return function(params, dispatchers)
  if not params or not params.files then
    return
  end

  for _, file in ipairs(params.files) do
    rename_note(file, dispatchers)
  end
end
