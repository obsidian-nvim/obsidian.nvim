local function coerce(v)
  if v == vim.NIL then
    return nil
  else
    return v
  end
end

---@param path table
---@param k string
---@param factory fun(path: obsidian.Path): any
---@private
local function cached_get(path, k, factory)
  local cache_key = "__" .. k
  local v = rawget(path, cache_key)
  if v == nil then
    v = factory(path)
    if v == nil then
      v = vim.NIL
    end
    path[cache_key] = v
  end
  return coerce(v)
end

---@param path obsidian.Path
---@return string|?
---@private
local function get_name(path)
  local name = vim.fs.basename(path.filename)
  if not name or string.len(name) == 0 then
    return
  else
    return name
  end
end

---@param path obsidian.Path
---@return string[]
---@private
local function get_suffixes(path)
  ---@type string[]
  local suffixes = {}
  local name = path.name
  while name and string.len(name) > 0 do
    local s, e, suffix = string.find(name, "(%.[^%.]+)$")
    if s and e and suffix then
      name = string.sub(name, 1, s - 1)
      table.insert(suffixes, suffix)
    else
      break
    end
  end

  -- reverse the list.
  ---@type string[]
  local out = {}
  for i = #suffixes, 1, -1 do
    table.insert(out, suffixes[i])
  end
  return out
end

---@param path obsidian.Path
---@return string|?
---@private
local function get_suffix(path)
  local suffixes = path.suffixes
  if #suffixes > 0 then
    return suffixes[#suffixes]
  else
    return nil
  end
end

---@param path obsidian.Path
---@return string|?
---@private
local function get_stem(path)
  local name, suffix = path.name, path.suffix
  if not name then
    return
  elseif not suffix then
    return name
  else
    return string.sub(name, 1, string.len(name) - string.len(suffix))
  end
end

--- A `Path` class that provides a subset of the functionality of the Python `pathlib` library while
--- staying true to its API. It improves on a number of bugs in `plenary.path`.
---
---@toc_entry obsidian.Path
---
---@class obsidian.Path
---
---@field filename string The underlying filename as a string.
---@field name string|? The final path component, if any.
---@field suffix string|? The final extension of the path, if any.
---@field suffixes string[] A list of all of the path's extensions.
---@field stem string The final path component, without its suffix.
---@operator div(string|obsidian.Path): obsidian.Path
local Path = {}

Path.__tostring = function(self)
  return self.filename
end

Path.__eq = function(a, b)
  return a.filename == b.filename
end
Path.__div = function(self, other)
  return Path.new(vim.fs.joinpath(self.filename, tostring(other)))
end

Path.__index = function(self, k)
  local raw = rawget(Path, k)
  if raw then
    return raw
  end

  local factory
  if k == "name" then
    factory = get_name
  elseif k == "suffix" then
    factory = get_suffix
  elseif k == "suffixes" then
    factory = get_suffixes
  elseif k == "stem" then
    factory = get_stem
  end

  if factory then
    return cached_get(self, k, factory)
  end
end

--- Check if an object is an `obsidian.Path` object.
---
---@param path any
---
---@return boolean
Path.is_path_obj = function(path)
  if getmetatable(path) == Path then
    return true
  else
    return false
  end
end

-------------------------------------------------------------------------------
--- Constructors.
-------------------------------------------------------------------------------

--- Create a new path from a string.
---
---@param p string|obsidian.Path
---
---@return obsidian.Path
Path.new = function(p)
  local self = {}

  if Path.is_path_obj(p) then
    ---@cast p -string
    return p
  end

  self.filename = vim.fs.normalize(tostring(p))

  return setmetatable(self, Path)
end

--- Get a temporary path with a unique name.
---
---@param opts { suffix: string|? }|?
---
---@return obsidian.Path
Path.temp = function(opts)
  opts = opts or {}
  local tmpname = vim.fn.tempname()
  if opts.suffix then
    tmpname = tmpname .. opts.suffix
  end
  return Path.new(tmpname)
end

--- Get a path corresponding to a buffer.
---
---@param bufnr integer|? The buffer number or `0` / `nil` for the current buffer.
---
---@return obsidian.Path
Path.buffer = function(bufnr)
  return Path.new(vim.api.nvim_buf_get_name(bufnr or 0))
end

-------------------------------------------------------------------------------
--- Pure path methods.
-------------------------------------------------------------------------------

--- Return a new path with the suffix changed.
---
---@param suffix string
---@param should_append boolean|? should the suffix append a suffix instead of replacing one which may be there?
---
---@return obsidian.Path
Path.with_suffix = function(self, suffix, should_append)
  if not vim.startswith(suffix, ".") and string.len(suffix) > 1 then
    error(string.format("invalid suffix '%s'", suffix))
  elseif self.stem == nil then
    error(string.format("path '%s' has no stem", self.filename))
  end

  local new_name = ((should_append == true) and self.name or self.stem) .. suffix

  ---@type obsidian.Path|?
  local parent = nil
  if self.name ~= self.filename then
    parent = self:parent()
  end

  if parent then
    return parent / new_name
  else
    return Path.new(new_name)
  end
end

--- Returns true if the path is already in absolute form.
---
---@return boolean
Path.is_absolute = function(self)
  local api = require "obsidian.api"
  if
    vim.startswith(self.filename, "/")
    or (
      (api.get_os() == api.OSType.Windows or api.get_os() == api.OSType.Wsl)
      and string.match(self.filename, "^[%a]:/.*$")
    )
  then
    return true
  else
    return false
  end
end

--- Try to resolve a version of the path relative to the other.
--- An error is raised when it's not possible.
---
---@param other obsidian.Path|string
---
---@return obsidian.Path
Path.relative_to = function(self, other)
  other = Path.new(other)

  local other_fname = other.filename
  if not vim.endswith(other_fname, "/") then
    other_fname = other_fname .. "/"
  end

  if vim.startswith(self.filename, other_fname) then
    return Path.new(string.sub(self.filename, string.len(other_fname) + 1))
  end

  -- Edge cases when the paths are relative or under-specified, see tests.
  if not self:is_absolute() and not vim.startswith(self.filename, "./") and vim.startswith(other_fname, "./") then
    if other_fname == "./" then
      return self
    end

    local self_rel_to_cwd = Path.new "./" / self
    if vim.startswith(self_rel_to_cwd.filename, other_fname) then
      return Path.new(string.sub(self_rel_to_cwd.filename, string.len(other_fname) + 1))
    end
  end

  error(string.format("'%s' is not in the subpath of '%s'", self.filename, other.filename))
end

--- The logical parent of the path.
---
---@return obsidian.Path|?
Path.parent = function(self)
  local parent = vim.fs.dirname(self.filename)
  if parent ~= nil then
    return Path.new(parent)
  else
    return nil
  end
end

--- Get a list of the parent directories.
---
---@return obsidian.Path[]
Path.parents = function(self)
  return vim.iter(vim.fs.parents(self.filename)):map(Path.new):totable()
end

--- Check if the path is a parent of other. This is a pure path method, so it only checks by
--- comparing strings. Therefore in practice you probably want to `:resolve()` each path before
--- using this.
---
---@param other obsidian.Path|string
---
---@return boolean
Path.is_parent_of = function(self, other)
  other = Path.new(other)
  for _, parent in ipairs(other:parents()) do
    if parent == self then
      return true
    end
  end
  return false
end

---@return string?
---@private
Path.abspath = function(self)
  local path = vim.uv.fs_realpath(vim.fn.resolve(self.filename))
  return path
end

-------------------------------------------------------------------------------
--- Concrete path methods.
-------------------------------------------------------------------------------

--- Make the path absolute, resolving any symlinks.
--- If `strict` is true and the path doesn't exist, an error is raised.
---
---@param opts { strict: boolean }|?
---
---@return obsidian.Path
Path.resolve = function(self, opts)
  opts = opts or {}

  local realpath = self:abspath()
  if realpath then
    return Path.new(realpath)
  elseif opts.strict then
    error("FileNotFoundError: " .. self.filename)
  end

  -- File doesn't exist, but some parents might. Traverse up until we find a parent that
  -- does exist, and then put the path back together from there.
  local parents = self:parents()
  for _, parent in ipairs(parents) do
    local parent_realpath = parent:abspath()
    if parent_realpath then
      return Path.new(parent_realpath) / self:relative_to(parent)
    end
  end

  return self
end

--- Get OS stat results.
---
---@return table|?
Path.stat = function(self)
  local realpath = self:abspath()
  if realpath then
    local stat, _ = vim.uv.fs_stat(realpath)
    return stat
  end
end

--- Check if the path points to an existing file or directory.
---
---@return boolean
Path.exists = function(self)
  local stat = self:stat()
  return stat ~= nil
end

--- Check if the path points to an existing file.
---
---@return boolean
Path.is_file = function(self)
  local stat = self:stat()
  if stat == nil then
    return false
  else
    return stat.type == "file"
  end
end

--- Check if the path points to an existing directory.
---
---@return boolean
Path.is_dir = function(self)
  local stat = self:stat()
  if stat == nil then
    return false
  else
    return stat.type == "directory"
  end
end

--- Create a new directory at the given path.
---
---@param opts { mode: integer|?, parents: boolean|?, exist_ok: boolean|? }|?
Path.mkdir = function(self, opts)
  opts = opts or {}

  local mode = opts.mode or 448 -- 0700 -> decimal

  if self:is_dir() then
    return
  end

  if vim.uv.fs_mkdir(self.filename, mode) then
    return
  end

  if not opts.parents then
    error("FileNotFoundError: " .. tostring(self:parent()))
  end

  local parents = self:parents()
  for i = #parents, 1, -1 do
    if not parents[i]:is_dir() then
      parents[i]:mkdir { exist_ok = true, mode = mode }
    end
  end

  self:mkdir { mode = mode }
end

--- Create a file at this given path.
---
---@param opts { mode: integer|?, exist_ok: boolean|? }|?
Path.touch = function(self, opts)
  opts = opts or {}
  local mode = opts.mode or 420

  local resolved = self:resolve { strict = false }
  if resolved:exists() then
    local new_time = os.time()
    vim.uv.fs_utime(resolved.filename, new_time, new_time)
    return
  end

  local parent = resolved:parent()
  if parent and not parent:exists() then
    error("FileNotFoundError: " .. parent.filename)
  end

  local fd, err_name, err_msg = vim.uv.fs_open(resolved.filename, "w", mode)
  if not fd then
    error(err_name .. ": " .. err_msg)
  end
  vim.uv.fs_close(fd)
end

-- TODO: not implemented and not used, after we get to 0.11 we can simply use vim.fs.rm
--- Recursively remove an entire directory and its contents.
Path.rmtree = function() end

--- Make a path relative to the vault root, if possible, return a string
---
---@param opts { strict: boolean|? }|?
---
---@return string?
Path.vault_relative_path = function(self, opts)
  opts = opts or {}

  local api = require "obsidian.api"

  local root = api.resolve_workspace_dir(tostring(self))

  -- NOTE: we don't try to resolve the `path` here because that would make the path absolute,
  -- which may result in the wrong relative path if the current working directory is not within
  -- the vault.

  local ok, relative_path = pcall(function()
    return self:relative_to(root)
  end)

  if ok and relative_path then
    return tostring(relative_path)
  elseif not self:is_absolute() then
    return tostring(self)
  elseif opts.strict then
    error(string.format("failed to resolve '%s' relative to vault root '%s'", self, Obsidian.workspace.root))
  end
end

return Path
