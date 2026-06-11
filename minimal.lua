vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua")()

vim.fn.mkdir(".repro/vault", "p")

vim.o.conceallevel = 2

local cwd = vim.uv.cwd()

-- NOTE: if you want to try native lsp completion, see `:Obsidian help Completion`

local plugins = {
  {
    "obsidian-nvim/obsidian.nvim",
    dir = cwd,
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false,
      workspaces = {
        {
          name = "test",
          path = vim.fs.joinpath(cwd, ".repro", "vault"),
        },
      },
      ui = {},
    },
  },

  -- **Choose your renderer**
  -- { "MeanderingProgrammer/render-markdown.nvim", dependencies = { "echasnovski/mini.icons" }, opts = {} },
  -- { "OXY2DEV/markview.nvim", lazy = false },

  -- **Choose your picker**
  -- "nvim-telescope/telescope.nvim",
  -- { "folke/snacks.nvim", opts = { picker = { enabled = true } } },
  -- "ibhagwan/fzf-lua",
  -- "echasnovski/mini.pick",

  -- **Choose your completion engine**
  -- {
  --   "hrsh7th/nvim-cmp",
  --   dependencies = {
  --     "hrsh7th/cmp-nvim-lsp",
  --   },
  --   config = function()
  --     local cmp = require "cmp"
  --     cmp.setup {
  --       mapping = cmp.mapping.preset.insert {
  --         ["<C-e>"] = cmp.mapping.abort(),
  --         ["<C-y>"] = cmp.mapping.confirm { select = true },
  --       },
  --       sources = {
  --         { name = "nvim_lsp" },
  --       },
  --     }
  --   end,
  -- },
  -- {
  --   "saghen/blink.cmp",
  --   version = "1.*",
  --   opts = {},
  -- },
  -- {
  --   "nvim-mini/mini.nvim",
  --   config = function()
  --     require("mini.completion").setup {}
  --   end,
  -- },
}

require("lazy.minit").repro { spec = plugins }

-- vim.cmd "checkhealth obsidian"
