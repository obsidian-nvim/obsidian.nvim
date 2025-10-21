local Path = require "obsidian.path"
local child = MiniTest.new_child_neovim()

local M = {}

---Return test set and child instance
M.child_vault = function(hooks)
  hooks = hooks or {}
  return MiniTest.new_set {
    hooks = {
      pre_case = function()
        child.restart { "-u", "scripts/minimal_init.lua" }
        child.lua [[
local Path = require "obsidian.path"
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
  footer = {
    enabled = false,
  },
  log_level = vim.log.levels.WARN,
}
        ]]
        if hooks.pre_case then
          child.lua(hooks.pre_case)
        end
      end,
      post_case = function()
        child.lua [[vim.fn.delete(tostring(Obsidian.dir), "rf")]]
        child.stop()
      end,
    },
  },
    child
end

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
        completion = {
          blink = false,
          nvim_cmp = false,
        },
        log_level = vim.log.levels.WARN,
      }

      Path.new(dir / "templates"):mkdir()
    end,
    post_case = function()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

return M
