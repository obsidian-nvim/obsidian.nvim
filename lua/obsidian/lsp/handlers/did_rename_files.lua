local obsidian = require "obsidian"
local Note = obsidian.Note
local api = obsidian.api

---@param file lsp.FileRename
---@param dispatchers table
local function rename_note(file, dispatchers)
  local new_path = vim.uri_to_fname(file.newUri)
  local note = Note.from_file(new_path)
  local new_name = vim.fs.basename(new_path):gsub("%.md$", "")
  note:rename(new_name, {
    old_path = vim.uri_to_fname(file.oldUri),
    new_path = new_path,
    include_file_rename = false,
    apply = false,
    update_buffers = false,
    check_unique = false,
  }, function(err, edit, meta)
    if err or not edit then
      return
    end

    if Obsidian.opts.link.auto_update ~= true then
      local prompt = ("Update %d reference(s) across %d file(s) for renamed note '%s'?"):format(
        meta.count,
        vim.tbl_count(meta.path_lookup),
        new_name
      )
      local choice = api.confirm(prompt)
      if choice ~= "Yes" then
        return
      end
    end

    dispatchers.server_request("workspace/applyEdit", {
      label = "Update renamed note references",
      edit = edit,
    })
  end)
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
