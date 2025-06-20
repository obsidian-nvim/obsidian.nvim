local Path = require "obsidian.path"
local obsidian = require "obsidian"

local M = {}

---Get a client in a temporary directory.
---
---@param f fun(client: obsidian.Client)
---@param client_opts obsidian.config.ClientOpts
---@param opts { files: table<string, string[]> }
M.with_tmp_client = function(f, dir, client_opts, opts)
  local tmp
  if not dir then
    tmp = true
    dir = dir or Path.temp { suffix = "-obsidian" }
    dir:mkdir { parents = true }
  end

  local client = obsidian.new_from_dir(tostring(dir))
  client.dir = dir

  if client_opts then
    client.opts = vim.deepcopy(client_opts)
  end

  if opts and opts.files then
    for fname, lines in pairs(opts.files) do
      vim.fn.writefile(lines, vim.fs.joinpath(tostring(client.dir), fname))
    end
  end

  local ok, err = pcall(f, client)

  if tmp then
    vim.fn.delete(tostring(dir), "rf")
  end

  if not ok then
    error(err)
  end
end

M.fixtures = vim.fs.joinpath(vim.uv.cwd(), "tests", "fixtures", "notes")

return M
