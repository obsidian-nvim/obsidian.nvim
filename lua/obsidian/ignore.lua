local gitignore = require("obsidian.lib.glob").gitignore
local Path = require "obsidian.path"

local M = {}

M._cache = {}

local SYSNAME = vim.uv.os_uname().sysname

local function is_absolute_path(path)
  if vim.startswith(path, "/") then
    return true
  end
  if SYSNAME == "Windows_NT" and path:match "^%a:[/\\]" then
    return true
  end
  return false
end

M._is_absolute_path = is_absolute_path

local function get_vault_relative(path)
  if not Obsidian or not Obsidian.dir then
    return nil
  end

  local vault_root = Obsidian.dir
  local path_obj = Path.new(path)

  if vault_root:is_parent_of(path_obj) or vault_root == path_obj then
    local rel = vim.fs.normalize(tostring(path_obj)):sub(#vim.fs.normalize(tostring(vault_root)) + 1)
    if vim.startswith(rel, "/") then
      rel = rel:sub(2)
    end
    return rel
  end

  return nil
end

M._get_vault_relative = get_vault_relative

--- Build a checker function from a list of gitignore-style patterns.
--- Users should use simple gitignore style globs without modifiers,
--- and ripgrep compatibility is not guaranteed.
---@param patterns string[]
---@return Glob|nil
local function build_ignore_checker(patterns)
  if not patterns or vim.tbl_isempty(patterns) then
    return nil
  end

  local ignore_patterns = {}
  for _, pattern in ipairs(patterns) do
    if not vim.startswith(pattern, "!") then
      ignore_patterns[#ignore_patterns + 1] = pattern
    end
  end

  if vim.tbl_isempty(ignore_patterns) then
    return nil
  end

  local checker = gitignore(ignore_patterns, { ignoreCase = true })
  return checker
end

M._build_ignore_checker = build_ignore_checker

function M.get_checker()
  if not Obsidian or not Obsidian.opts then
    return nil
  end

  local ignore_filters = Obsidian.opts.file and Obsidian.opts.file.ignore_filters
  if not ignore_filters or vim.tbl_isempty(ignore_filters) then
    return nil
  end

  local key = table.concat(ignore_filters, "|")
  if M._cache[key] then
    return M._cache[key]
  end

  local checker = build_ignore_checker(ignore_filters)
  M._cache[key] = checker
  return checker
end

--- Check if a path should be ignored based on ignore_filters.
--- Users should use simple gitignore style globs without modifiers,
--- and ripgrep compatibility is not guaranteed.
---@param path string
---@return boolean
function M.is_ignored(path)
  local checker = M.get_checker()
  if not checker then
    return false
  end

  local rel_path
  if is_absolute_path(path) then
    rel_path = get_vault_relative(path) or vim.fs.normalize(path)
  else
    rel_path = vim.fs.normalize(path)
  end

  if not rel_path or rel_path == "" then
    return false
  end

  return checker(rel_path)
end

--- Check if a directory should be ignored based on ignore_filters.
--- Users should use simple gitignore style globs without modifiers,
--- and ripgrep compatibility is not guaranteed.
---@param dirname string
---@return boolean
function M.is_ignored_dir(dirname)
  local checker = M.get_checker()
  if not checker then
    return false
  end

  return checker(dirname)
end

function M.clear_cache()
  M._cache = {}
end

return M
