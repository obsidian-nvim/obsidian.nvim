local gitignore = require("obsidian.lib.glob").gitignore

local M = {}

M._cache = {}

local SYSNAME = vim.uv.os_uname().sysname

local function is_absolute_path(path)
  if vim.startswith(path, "/") then
    return true
  end
  -- Only check Windows-style absolute paths when actually on Windows.
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

  local vault_root = vim.fs.normalize(tostring(Obsidian.dir))
  path = vim.fs.normalize(path)

  if vim.startswith(path, vault_root) then
    local rel = path:sub(#vault_root + 1)
    -- Remove leading path separator if present
    if vim.startswith(rel, "/") then
      rel = rel:sub(2)
    end
    return rel
  end

  return nil
end

M._get_vault_relative = get_vault_relative

local function build_exclusion_checker(patterns)
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

M._build_exclusion_checker = build_exclusion_checker

function M.get_checker()
  if not Obsidian or not Obsidian.opts then
    return nil
  end

  local exclude_dir = Obsidian.opts.exclude_dir
  if not exclude_dir or vim.tbl_isempty(exclude_dir) then
    return nil
  end

  local key = table.concat(exclude_dir, "|")
  if M._cache[key] then
    return M._cache[key]
  end

  local checker = build_exclusion_checker(exclude_dir)
  M._cache[key] = checker
  return checker
end

function M.is_excluded(path)
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

function M.is_excluded_dir(dirname)
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
