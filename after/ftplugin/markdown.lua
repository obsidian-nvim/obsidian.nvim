local obsidian = require "obsidian"
local buf = vim.api.nvim_get_current_buf()
local buf_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))

local client = obsidian.get_client()

local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, client.opts.workspaces)
if not workspace then
  return -- if not in any workspace.
end

vim.o.commentstring = "%%%s%%"

vim.treesitter.start(buf, "markdown") -- for when user don't use nvim-treesitter
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt_local.foldlevel = 99
