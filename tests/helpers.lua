local Path = require "obsidian.path"
local obsidian = require "obsidian"
local child = MiniTest.new_child_neovim()

local M = {}

---Get a client in a temporary directory.
---
---@param f fun(client: obsidian.Client)
---@param opts obsidian.config.ClientOpts
M.with_tmp_client = function(f, dir, opts)
  local tmp
  if not dir then
    tmp = true
    dir = dir or Path.temp { suffix = "-obsidian" }
    dir:mkdir { parents = true }
  end

  local client = obsidian.new_from_dir(tostring(dir))

  if opts then
    Obsidian.opts = vim.deepcopy(opts)
  end
  local ok, err = pcall(f, client)

  if tmp then
    vim.fn.delete(tostring(dir), "rf")
  end

  if not ok then
    error(err)
  end
end

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
