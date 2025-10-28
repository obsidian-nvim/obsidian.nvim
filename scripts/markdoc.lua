vim.opt.rtp:append "deps/markdoc.nvim"

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
