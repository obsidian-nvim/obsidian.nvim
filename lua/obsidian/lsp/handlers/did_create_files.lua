local obsidian = require "obsidian"
local Note = obsidian.Note
local log = obsidian.log

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
        log.err(("Invalid filename %q: %s — deleting file"):format(stem, reason))
        dispatchers.server_request("workspace/applyEdit", {
          label = "Delete invalid filename",
          edit = {
            documentChanges = {
              {
                kind = "delete",
                uri = file.uri,
                options = {},
              },
            },
          },
        })
      end
    end
  end
end
