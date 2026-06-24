local obsidian = require "obsidian"
local Note = obsidian.Note
local log = obsidian.log
local api = obsidian.api
local rename = require "obsidian.lsp.handlers._rename"

---@param file lsp.FileRename
---@param dispatchers table
local function rename_note(file, dispatchers)
  local new_path = vim.uri_to_fname(file.newUri)
  local new_name = vim.fs.basename(new_path):gsub("%.md$", "")

  -- Guard: if the new filename is invalid, rename it back immediately so the
  -- invalid file never persists on disk (and never gets picked up by Obsidian Sync).
  local valid, reason = Note.is_valid_filename(new_name)
  if not valid then
    log.err(("Invalid filename %q: %s — reverting rename"):format(new_name, reason))
    dispatchers.server_request("workspace/applyEdit", {
      label = "Revert invalid filename",
      edit = {
        documentChanges = {
          {
            kind = "rename",
            oldUri = file.newUri,
            newUri = file.oldUri,
            options = {},
          },
        },
      },
    })
    return
  end

  local note = Note.from_file(new_path)
  rename.build_edit(note, new_name, {
    old_path = vim.uri_to_fname(file.oldUri),
    new_path = new_path,
    include_file_rename = false,
  }, function(edit, meta)
    if not edit then
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
