-- Repro for obsidian.nvim + experimental vim.ui.img runtime.
-- Run from this repo with:
--   NVIM_IMG_RUNTIME=~/Clone/neovim/runtime nvim --clean -u minimal-img.lua
--
-- Why not `VIMRUNTIME=~/Clone/neovim/runtime`?
-- The local img branch is behind main, and replacing the whole runtime can break
-- unrelated core modules. Prepending the branch runtimepath lets us load only the
-- experimental `vim.ui.img` modules while keeping the working Nvim runtime.

vim.env.LAZY_STDPATH = ".repro-img"

local img_runtime = vim.fn.expand(vim.env.NVIM_IMG_RUNTIME or "~/Clone/neovim/runtime")
if vim.uv.fs_stat(img_runtime) then
  vim.opt.runtimepath:prepend(img_runtime)
else
  vim.notify("NVIM_IMG_RUNTIME not found: " .. img_runtime, vim.log.levels.WARN)
end

-- Force the WIP API from the img branch onto vim.ui.img.
package.loaded["vim.ui.img"] = nil
package.loaded["vim.ui.img._kitty"] = nil
package.loaded["vim.ui.img._util"] = nil
vim.ui.img = require "vim.ui.img"

load(vim.fn.system "curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua")()

local cwd = vim.uv.cwd()
local vault = vim.fs.joinpath(cwd, ".repro-img", "vault")
vim.fn.mkdir(vault, "p")

vim.o.conceallevel = 2
vim.o.number = true
vim.o.signcolumn = "yes"

local function write_file(path, data)
  local fd = assert(io.open(path, "wb"))
  fd:write(data)
  fd:close()
end

-- 1x1 transparent PNG. Obsidian dimensions scale it up in the note.
local png = vim.base64.decode "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lJbT2wAAAABJRU5ErkJggg=="
write_file(vim.fs.joinpath(vault, "pixel.png"), png)
write_file(
  vim.fs.joinpath(vault, "image-test.md"),
  table.concat({
    "# vim.ui.img repro",
    "",
    "Below should render with Obsidian pixel dimensions converted to cells:",
    "",
    "![[pixel.png|180x90]]",
    "",
    "Width-only syntax preserves aspect ratio:",
    "",
    "![[pixel.png|120]]",
    "",
  }, "\n")
)

local plugins = {
  {
    "obsidian-nvim/obsidian.nvim",
    dir = cwd,
    opts = {
      legacy_commands = false,
      workspaces = {
        { name = "img", path = vault },
      },
      image = {
        enabled = true,
        relative = "buffer",
        max_width = 80,
        max_height = 40,
        debounce = 20,
        conceal = true,
      },
    },
  },
}

require("lazy.minit").repro { spec = plugins }

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = function()
    vim.cmd.edit(vim.fs.joinpath(vault, "image-test.md"))
    vim.notify("Loaded vim.ui.img from: " .. img_runtime, vim.log.levels.INFO)
  end,
})

vim.keymap.set("n", "<leader>ir", function()
  require("obsidian.image").refresh(0, true)
end, { desc = "Refresh obsidian images" })

vim.keymap.set("n", "<leader>i+", function()
  require("obsidian.image").increase_size()
end, { desc = "Image bigger" })

vim.keymap.set("n", "<leader>i-", function()
  require("obsidian.image").decrease_size()
end, { desc = "Image smaller" })

vim.keymap.set("n", "<leader>ix", function()
  vim.ui.img.del(math.huge)
end, { desc = "Delete vim.ui.img images" })
