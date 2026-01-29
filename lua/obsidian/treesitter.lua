local M = {}

local function setup_env()
  -- Make sure any spawned `tree-sitter generate` sees these
  vim.env.EXTENSION_WIKI_LINK = "1"
  vim.env.EXTENSION_TAGS = "1"
end

M.setup = function()
  local ok = pcall(require, "nvim-treesitter")
  print(ok, "called")
  if not ok then
    return
  end

  setup_env()
  vim.api.nvim_create_autocmd("User", {
    pattern = "TSUpdate",
    callback = function()
      local p = require "nvim-treesitter.parsers"
      -- Force regeneration for env flags to take effect
      p.markdown_inline.install_info.generate = true
      p.markdown_inline.install_info.generate_from_json = false -- <-- use grammar.js
    end,
  })
  vim.cmd "TSUninstall markdown markdown_inline"
  vim.cmd.TSUpdate()
end

return M
