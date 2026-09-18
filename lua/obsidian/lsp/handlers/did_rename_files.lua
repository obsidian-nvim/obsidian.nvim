local obsidian = require "obsidian"
local Note = obsidian.Note
local Path = obsidian.Path
local api = obsidian.api
local rename = require "obsidian.note.rename"

local function apply_reference_edit(edit, meta, kind, name, dispatchers)
  if not edit then
    return
  end

  if Obsidian.opts.link.auto_update ~= true then
    local prompt = ("Update %d reference(s) across %d file(s) for renamed %s '%s'?"):format(
      meta.count,
      vim.tbl_count(meta.path_lookup),
      kind,
      name
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
end

---@param file lsp.FileRename
---@param dispatchers table
local function rename_note(file, dispatchers)
  local new_path = vim.uri_to_fname(file.newUri)
  local note = Note.from_file(new_path)
  if not note then
    return
  end

  local new_name = vim.fs.basename(new_path):gsub("%.md$", "")
  note:build_rename_edit(new_name, {
    old_path = vim.uri_to_fname(file.oldUri),
    new_path = new_path,
    include_file_rename = false,
    dir = api.resolve_workspace_dir(new_path),
  }, function(edit, meta)
    apply_reference_edit(edit, meta, "note", new_name, dispatchers)
  end)
end

---@param file lsp.FileRename
---@param dispatchers table
local function rename_folder(file, dispatchers)
  local old_folder = Path.new(vim.uri_to_fname(file.oldUri))
  local new_folder = Path.new(vim.uri_to_fname(file.newUri))
  local path_pairs = {}

  for path in api.dir(new_folder) do
    local new_path = Path.new(path)
    local rel_path = new_path:relative_to(new_folder)
    path_pairs[#path_pairs + 1] = {
      old_path = tostring(old_folder / rel_path),
      new_path = tostring(new_path),
    }
  end

  if #path_pairs == 0 then
    return
  end

  rename.build_edit_for_paths(path_pairs, {
    include_file_rename = false,
    include_stem_refs = false,
    dir = api.resolve_workspace_dir(new_folder),
  }, function(edit, meta)
    apply_reference_edit(edit, meta, "folder", new_folder.name or tostring(new_folder), dispatchers)
  end)
end

---@param params lsp.RenameFilesParams
---@param dispatchers table
return function(params, dispatchers)
  if not params or not params.files then
    return
  end

  for _, file in ipairs(params.files) do
    local new_path = Path.new(vim.uri_to_fname(file.newUri))
    if new_path:is_dir() then
      rename_folder(file, dispatchers)
    else
      rename_note(file, dispatchers)
    end
  end
end
