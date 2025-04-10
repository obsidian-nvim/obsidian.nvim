vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua")()

vim.fn.mkdir(".repro/vault", "p")

vim.o.conceallevel = 2

local plugins = {
  {
    "obsidian-nvim/obsidian.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    dir = "~/Plugins/obsidian.nvim/",
    opts = {
      workspaces = {
        {
          name = "test",
          path = vim.fs.joinpath(vim.uv.cwd(), ".repro", "vault"),
        },
      },
    },
  },

  -- **Choose your renderer**
  { "MeanderingProgrammer/render-markdown.nvim", dependencies = { "echasnovski/mini.icons" }, opts = {} },
  -- { "OXY2DEV/markview.nvim", lazy = false },

  -- **Choose your picker**
  "nvim-telescope/telescope.nvim",
  -- "folke/snacks.nvim",
  -- "ibhagwan/fzf-lua",
  -- "echasnovski/mini.pick",
}

require("lazy.minit").repro { spec = plugins }

vim.cmd "checkhealth obsidian"
