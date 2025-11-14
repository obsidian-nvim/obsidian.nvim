vim.opt.rtp:append "deps/markdoc.nvim"
vim.opt.rtp:append "deps/nvim-treesitter"

local install_dir = vim.fs.joinpath(vim.uv.cwd(), "/deps/site")

require("nvim-treesitter").setup {
  install_dir = install_dir,
}

local filetypes = { "markdown", "markdown_inline", "html" }

local nts = require "nvim-treesitter"
nts.install(filetypes):wait()

for _, ft in ipairs(filetypes) do
  vim.treesitter.language.add(ft, {
    path = vim.fs.joinpath(install_dir, ("parser/%s.so"):format(ft)),
  })
end

require("markdoc").convert_file("README.md", {
  generic = {
    filename = "doc/obsidian.nvim.txt", -- TODO: obsidian.txt
    force_write = true,
    header = {
      desc = "a plugin for writing and navigating an Obsidian vault",
      tag = "obsidian.nvim",
    },
  },
})
