vim.opt.rtp:append "deps/markdoc.nvim"
require("markdoc").setup {}
vim.cmd "Doc README.md"
