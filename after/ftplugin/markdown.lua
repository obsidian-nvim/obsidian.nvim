local obsidian = require "obsidian"
local buf = vim.api.nvim_get_current_buf()
local buf_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))

local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, Obsidian.opts.workspaces)
if not workspace then
  return -- if not in any workspace.
end

vim.o.commentstring = "%%%s%%"

local win = vim.api.nvim_get_current_win()

vim.treesitter.start(buf, "markdown") -- for when user don't use nvim-treesitter
vim.wo[win].foldmethod = "expr"
vim.wo[win].foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo[win].foldlevel = 99
