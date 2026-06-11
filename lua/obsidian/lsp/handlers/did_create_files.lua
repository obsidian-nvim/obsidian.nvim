local obsidian = require "obsidian"
local Note = obsidian.Note
local log = obsidian.log

---@param uri string
---@param stem string
---@param dispatchers table
local function rename_invalid_file(uri, stem, dispatchers)
  local ok, new_stem = pcall(Note.prompt_for_valid_filename, stem)
  if not ok then
    log.err(("Invalid filename %q — deleting file"):format(stem))
    dispatchers.server_request("workspace/applyEdit", {
      label = "Delete invalid filename",
      edit = {
        documentChanges = {
          {
            kind = "delete",
            uri = uri,
            options = {},
          },
        },
      },
    })
    return
  end

  local new_path = vim.fs.joinpath(vim.fs.dirname(vim.uri_to_fname(uri)), new_stem .. ".md")
  dispatchers.server_request("workspace/applyEdit", {
    label = "Rename invalid filename",
    edit = {
      documentChanges = {
        {
          kind = "rename",
          oldUri = uri,
          newUri = vim.uri_from_fname(new_path),
          options = {},
        },
      },
    },
  })
end

---@param params lsp.CreateFilesParams
---@param dispatchers table
return function(params, dispatchers)
  if not params or not params.files then
    return
  end

  for _, file in ipairs(params.files) do
    local path = vim.uri_to_fname(file.uri)
    if vim.endswith(path, ".md") then
      local stem = vim.fs.basename(path):gsub("%.md$", "")
      local valid, reason = Note.is_valid_filename(stem)
      if not valid then
        log.err(("Invalid filename %q: %s"):format(stem, reason))
        rename_invalid_file(file.uri, stem, dispatchers)
      end
    end
  end
end
