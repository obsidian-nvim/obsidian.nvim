-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.rtp:append(vim.uv.cwd())
-- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
-- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
vim.opt.rtp:append "deps/mini.test"

-- Keep expected warnings/deprecations out of test output, but still show errors.
local notify = vim.notify
vim.notify = function(msg, level, opts)
  if level ~= nil and level >= vim.log.levels.ERROR then
    notify(msg, level, opts)
  end
end
vim.notify_once = vim.notify

-- Set up 'mini.test'
require("mini.test").setup()
