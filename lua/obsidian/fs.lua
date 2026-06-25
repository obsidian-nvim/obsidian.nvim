local M = {}
local gitignore = require("obsidian.lib.glob").gitignore
local ignore = require "obsidian.ignore"
local util = require "obsidian.util"

local DIR_MODE = assert(tonumber("755", 8))

---@param path string
---@return string
function M.unique_path(path)
  if not vim.uv.fs_stat(path) then
    return path
  end

  local parent = vim.fs.dirname(path)
  local basename = vim.fs.basename(path)
  local stem, ext = basename:match "^(.*)%.([^%.]+)$"
  if stem and stem ~= "" then
    ext = "." .. ext
  else
    stem = basename
    ext = ""
  end

  local candidate = util.find_unique(path, function(candidate)
    return vim.uv.fs_stat(candidate) ~= nil
  end, function(_, i)
    return vim.fs.joinpath(parent, ("%s-%d%s"):format(stem, i, ext))
  end, 1000)

  if candidate then
    return candidate
  end
  error("failed to find unique path for " .. path)
end

---@param path string
---@param opts { mode: integer|?, parents: boolean|? }|?
function M.mkdir(path, opts)
  opts = opts or {}
  path = vim.fs.normalize(path)
  if path == "" or path == "." then
    return
  end

  local stat = vim.uv.fs_stat(path)
  if stat then
    if stat.type == "directory" then
      return
    end
    error("path exists and is not a directory: " .. path)
  end

  if opts.parents then
    local parent = vim.fs.dirname(path)
    if parent and parent ~= path then
      M.mkdir(parent, opts)
    end
  end

  local ok, err = vim.uv.fs_mkdir(path, opts.mode or DIR_MODE)
  if not ok then
    stat = vim.uv.fs_stat(path)
    if stat and stat.type == "directory" then
      return
    end
    error("failed to create directory " .. path .. ": " .. tostring(err))
  end
end

---@param src string
---@param dest string
function M.copy_dir(src, dest)
  M.mkdir(dest, { parents = true })
  local handle = vim.uv.fs_scandir(src)
  if not handle then
    return
  end

  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    local src_child = vim.fs.joinpath(src, name)
    local dest_child = vim.fs.joinpath(dest, name)
    if typ == "directory" then
      M.copy_dir(src_child, dest_child)
    else
      M.mkdir(vim.fs.dirname(dest_child), { parents = true })
      vim.uv.fs_copyfile(src_child, dest_child)
    end
  end
end

---@param path string
---@return boolean
function M.rm(path)
  if not vim.uv.fs_lstat(path) then
    return false
  end

  return pcall(vim.fs.rm, path, { recursive = true })
end

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
      local not_ignored = not ignore.is_ignored_dir(dirname)
      return not_dot and not_template and not_gitignored and not_ignored
    end,
  }

  return vim
    .iter(vim.fs.dir(dir, dir_opts))
    :filter(function(path)
      local is_markdown = vim.endswith(path, ".md") or vim.endswith(path, ".qmd") or vim.endswith(path, ".base")
      local not_gitignored = not parser(path)
      local not_dot = not vim.startswith(path, ".")
      local not_ignored = not ignore.is_ignored(path)
      return is_markdown and not_gitignored and not_dot and not_ignored
    end)
    :map(function(path)
      return vim.fs.joinpath(dir, path)
    end)
end

return M
