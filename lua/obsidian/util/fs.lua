local function split_path(path)
  local parts = {}
  for part in path:gmatch "[^/]+" do
    table.insert(parts, part)
  end
  return parts
end

local function join_path(parts)
  return table.concat(parts, "/")
end

local uv = vim.uv

-- Can't use `has('win32')` because the `nvim -ll` test runner doesn't support `vim.fn` yet.
local sysname = uv.os_uname().sysname:lower()
local iswin = not not (sysname:find "windows" or sysname:find "mingw")
local os_sep = iswin and "\\" or "/"

--- Expand tilde (~) character at the beginning of the path to the user's home directory.
---
--- @param path string Path to expand.
--- @param sep string|nil Path separator to use. Uses os_sep by default.
--- @return string Expanded path.
local function expand_home(path, sep)
  sep = sep or os_sep

  if vim.startswith(path, "~") then
    local home = uv.os_homedir() or "~" --- @type string

    if home:sub(-1) == sep then
      home = home:sub(1, -2)
    end

    path = home .. path:sub(2) --- @type string
  end

  return path
end

--- @param path string Path to split.
--- @return string, string, boolean : prefix, body, whether path is invalid.
local function split_windows_path(path)
  local prefix = ""

  --- Match pattern. If there is a match, move the matched pattern from the path to the prefix.
  --- Returns the matched pattern.
  ---
  --- @param pattern string Pattern to match.
  --- @return string|nil Matched pattern
  local function match_to_prefix(pattern)
    local match = path:match(pattern)

    if match then
      prefix = prefix .. match --[[ @as string ]]
      path = path:sub(#match + 1)
    end

    return match
  end

  local function process_unc_path()
    return match_to_prefix "[^/]+/+[^/]+/+"
  end

  if match_to_prefix "^//[?.]/" then
    -- Device paths
    local device = match_to_prefix "[^/]+/+"

    -- Return early if device pattern doesn't match, or if device is UNC and it's not a valid path
    if not device or (device:match "^UNC/+$" and not process_unc_path()) then
      return prefix, path, false
    end
  elseif match_to_prefix "^//" then
    -- Process UNC path, return early if it's invalid
    if not process_unc_path() then
      return prefix, path, false
    end
  elseif path:match "^%w:" then
    -- Drive paths
    prefix, path = path:sub(1, 2), path:sub(3)
  end

  -- If there are slashes at the end of the prefix, move them to the start of the body. This is to
  -- ensure that the body is treated as an absolute path. For paths like C:foo/bar, there are no
  -- slashes at the end of the prefix, so it will be treated as a relative path, as it should be.
  local trailing_slash = prefix:match "/+$"

  if trailing_slash then
    prefix = prefix:sub(1, -1 - #trailing_slash)
    path = trailing_slash .. path --[[ @as string ]]
  end

  return prefix, path, true
end

-- neovim standard implementation for backward compatibility 0.10.4
--- @param path string Path
--- @return string Absolute path
local function abspath(path)
  -- TODO(justinmk): mark f_fnamemodify as API_FAST and use it, ":p:h" should be safe...

  vim.validate("path", path, "string")

  -- Expand ~ to user's home directory
  path = expand_home(path)

  -- Convert path separator to `/`
  path = path:gsub(os_sep, "/")

  local prefix = ""

  if iswin then
    prefix, path = split_windows_path(path)
  end

  if prefix == "//" or vim.startswith(path, "/") then
    -- Path is already absolute, do nothing
    return prefix .. path
  end

  -- Windows allows paths like C:foo/bar, these paths are relative to the current working directory
  -- of the drive specified in the path
  local cwd = (iswin and prefix:match "^%w:$") and uv.fs_realpath(prefix) or uv.cwd()
  assert(cwd ~= nil)
  -- Convert cwd path separator to `/`
  cwd = cwd:gsub(os_sep, "/")

  if path == "." then
    return cwd
  end
  -- Prefix is not needed for expanding relative paths, `cwd` already contains it.
  return vim.fs.joinpath(cwd, path)
end

---@param base string
---@param target string
---@return string|?
local function relpath(base, target)
  base = vim.fs.normalize(abspath(base))
  target = vim.fs.normalize(abspath(target))

  if base == target then
    return "."
  end

  local base_parts = split_path(base)
  local target_parts = split_path(target)

  -- Find common prefix
  local i = 1
  while i <= #base_parts and i <= #target_parts and base_parts[i] == target_parts[i] do
    i = i + 1
  end

  -- Steps up from base to common ancestor
  local ups = {}
  for _ = i, #base_parts do
    table.insert(ups, "..")
  end

  -- Steps down to target from common ancestor
  local downs = {}
  for j = i, #target_parts do
    table.insert(downs, target_parts[j])
  end

  local rel_parts = {}
  vim.list_extend(rel_parts, ups)
  vim.list_extend(rel_parts, downs)

  return #rel_parts > 0 and join_path(rel_parts) or "."
end

return {
  relpath = relpath,
}
