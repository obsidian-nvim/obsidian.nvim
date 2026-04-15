vim.env.LAZY_STDPATH = ".repro"
load(vim.fn.system "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua")()

vim.fn.mkdir(".repro/vault", "p")

vim.o.conceallevel = 2

local cwd = vim.uv.cwd()

local chars = {}
for i = 32, 126 do
  table.insert(chars, string.char(i))
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)

    if client and client.name == "obsidian-ls" then
      client.server_capabilities.completionProvider.triggerCharacters = chars
      -- vim.bo[ev.buf].completeopt = "menuone,noselect,fuzzy,nosort" -- noselect to make sure no accidentally accept and create new notes, others are not necessary
      -- vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})

local plugins = {
  {
    "obsidian-nvim/obsidian.nvim",
    dir = cwd,
    opts = {
      legacy_commands = false,
      workspaces = {
        {
          name = "test",
          path = vim.fs.joinpath(cwd, ".repro", "vault"),
        },
      },
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
  --   opts = {
  --     fuzzy = { implementation = "lua" }, -- no need to build binary
  --   },
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
