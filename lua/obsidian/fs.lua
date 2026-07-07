local M = {}
local gitignore = require("obsidian.lib.glob").gitignore
local ignore = require "obsidian.ignore"

---@return Glob|function
local function parse_gitignore(dir)
  local ignore_file = vim.fs.joinpath(dir, ".gitignore")
  if not vim.uv.fs_stat(ignore_file) then
    return function(_fname)
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
---@return any
M.dir = function(dir)
  dir = tostring(dir)
  local parser = parse_gitignore(dir)
  local function is_gitignored(path)
    if type(parser) == "function" then
      return parser(path)
    end
    return parser:check(path)
  end
  local api = require "obsidian.api"

  local dir_opts = {
    depth = 10,
    skip = function(dirname)
      local not_dot = not vim.startswith(dirname, ".")
      local not_template = dirname ~= vim.fs.basename(tostring(api.templates_dir()))
      local not_gitignored = not is_gitignored(dirname)
      local not_ignored = not ignore.is_ignored_dir(dirname)
      return not_dot and not_template and not_gitignored and not_ignored
    end,
  }

  return coroutine.wrap(function()
    for path in vim.fs.dir(dir, dir_opts) do
      local is_markdown = vim.endswith(path, ".md") or vim.endswith(path, ".qmd") or vim.endswith(path, ".base")
      local not_gitignored = not is_gitignored(path)
      local not_dot = not vim.startswith(path, ".")
      local not_ignored = not ignore.is_ignored(path)
      if is_markdown and not_gitignored and not_dot and not_ignored then
        coroutine.yield(vim.fs.joinpath(dir, path))
      end
    end
  end)
end

return M
