local obsidian = require "obsidian"
local buf = vim.api.nvim_get_current_buf()
local buf_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))

local client = obsidian.get_client()

local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, client.opts.workspaces)
if not workspace then
  return -- if not in any workspace.
end

vim.o.commentstring = "%%%s%%"
