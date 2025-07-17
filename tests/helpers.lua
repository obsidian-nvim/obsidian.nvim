local Path = require "obsidian.path"
local obsidian = require "obsidian"

local M = {}

---Create a new Obsidian client in a given vault directory.
---
---@param dir string
---@param opts obsidian.config.ClientOpts|?
---@return obsidian.Client
local new_from_dir = function(dir, opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, obsidian.config.default)
  opts.workspaces = { { path = dir, strict = true } }
  return obsidian.Client.new(opts)
end

---Get a client in a temporary directory.
---
---@param f fun(client: obsidian.Client)
---@param opts obsidian.config.ClientOpts
M.with_tmp_client = function(f, dir, opts)
  local tmp
  local templates_dir
  if not dir then
    tmp = true
    dir = dir or Path.temp { suffix = "-obsidian" }
    dir:mkdir { parents = true }

    if opts and opts.templates and opts.templates.folder then
      templates_dir = dir / opts.templates.folder
      templates_dir:mkdir()
    end
  end

  local client = new_from_dir(tostring(dir), opts)
  local ok, err = pcall(f, client)

  if tmp then
    vim.fn.delete(tostring(dir), "rf")
  end

  if templates_dir then
    vim.fn.delete(tostring(templates_dir), "rf")
  end

  if not ok then
    error(err)
  end
end

M.temp_vault = MiniTest.new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
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

return M
