local Path = require "obsidian.path"
local child = MiniTest.new_child_neovim()

local M = {}

M.temp_vault = MiniTest.new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        legacy_commands = false,
        workspaces = { {
          path = tostring(dir),
        } },
        templates = {
          folder = "templates",
        },
      }

      Path.new(dir / "templates"):mkdir()
    end,
    post_case = function()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

M.new_set_with_setup = function()
  return MiniTest.new_set {
    hooks = {
      pre_case = function()
        child.restart { "-u", "scripts/minimal_init_with_setup.lua" }
      end,
      post_once = function()
        child.lua [[vim.fn.delete(tostring(Obsidian.dir), "rf")]]
        child.stop()
      end,
    },
  },
    child
end

return M
