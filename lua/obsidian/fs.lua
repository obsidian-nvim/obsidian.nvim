local M = {}
local gitignore = require("obsidian.lib.glob").gitignore

---@return Glob|function
local function parse_gitignore(dir)
  local ignore_file = vim.fs.joinpath(dir, ".gitignore")
  if not vim.uv.fs_stat(ignore_file) then
    return function(fname)
      _ = fname
      return false
    end
  end
  local lines = vim.fn.readfile(ignore_file)
  local parser = gitignore(lines, { ignoreCase = true })
  return parser
end

--- Return a iter like `vim.fs.dir` but on a dir of notes.
---
---@param dir string | obsidian.Path
---@return Iter
M.dir = function(dir)
  dir = tostring(dir)
  local parser = parse_gitignore(dir)
  local api = require "obsidian.api"

  local dir_opts = {
    depth = 10,
    skip = function(dirname)
      local not_dot = not vim.startswith(dirname, ".")
      local not_template = dirname ~= vim.fs.basename(tostring(api.templates_dir()))
      local not_gitignored = not parser(dirname)
      return not_dot and not_template and not_gitignored
    end,
  }

  return vim
    .iter(vim.fs.dir(dir, dir_opts))
    :filter(function(path)
      local is_markdown = vim.endswith(path, ".md") or vim.endswith(path, ".qmd")
      local not_gitignored = not parser(path)
      local not_dot = not vim.startswith(path, ".")
      return is_markdown and not_gitignored and not_dot
    end)
    :map(function(path)
      return vim.fs.joinpath(dir, path)
    end)
end

return M
