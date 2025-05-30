local M = {}

local obsidian = require "obsidian"

---Get a client in a temporary directory.
---@param testid string A unique ID for the tests which prevents directory collision
---@param templates_dir string The template directory
---@return obsidian.Client
M.get_tmp_client = function(testid, templates_dir)
  templates_dir = templates_dir or "templates"

  local tmpdir = "tmp-vault-" .. testid

  vim.loop.fs_mkdir(tmpdir, 448) -- <-- octal representation of 700 (RWX)
  vim.loop.fs_mkdir(tmpdir .. "/" .. templates_dir, 448)

  local client = obsidian.new_from_dir(tmpdir)
  client.opts.templates.folder = "templates"
  return client
end

--- Clean up a client, removing any resources created during `get_tmp_client`
--- @param client obsidian.Client The Client
M.cleanup_tmp_client = function(client)
  local path = client.dir:resolve()
  vim.fs.rm(tostring(path), { recursive = true, force = true })
end

return M
