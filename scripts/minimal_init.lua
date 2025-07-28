-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.rtp:append(vim.uv.cwd())
-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
vim.opt.rtp:append "deps/mini.test"

-- Set up 'mini.test'
require("mini.test").setup()
