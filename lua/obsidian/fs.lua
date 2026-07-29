local M = {}

local gitignore = require("obsidian.lib.glob").gitignore
local ignore = require "obsidian.ignore"

---@class obsidian.fs.WalkOpts
---@field hidden? boolean Include dotfiles and descend into dot-directories.
---@field gitignore? boolean Respect the root's `.gitignore` (default: true).
---@field ignore? boolean|fun(path: string, type: string): boolean Respect configured ignore filters, or provide a custom ignore predicate.
---@field predicate? fun(path: string, type: string): boolean Only yield entries accepted by this predicate.
---@field prune? fun(path: string): boolean Prune matching directories.
---@field depth? integer Maximum traversal depth.
---@field sort_by? obsidian.config.SortBy|false Sort key (default: path).
---@field sort_reversed? boolean Reverse the selected sort order.
---@field stat? boolean Populate stat metadata even when it is not needed for sorting.
---@field type? "file"|"directory" Entry type to yield (default: file).

---@class obsidian.fs.FindAsyncOpts: obsidian.fs.WalkOpts
---@field batch_size? integer Entries to inspect in each event-loop turn (default: 200).

---@class obsidian.fs.WalkEntry
---@field path string
---@field relative_path string
---@field type string
---@field stat uv.fs_stat.result?

local function is_hidden(path)
  for part in path:gmatch "[^/\\]+" do
    if vim.startswith(part, ".") then
      return true
    end
  end
  return false
end

---@class obsidian.fs.GitignoreRecord
---@field parser Glob
---@field path string
---@field kind "file"|"directory"

---@param root string
---@return fun(relative_path: string, kind: string): boolean
local function gitignore_checker(root)
  ---@type table<string, obsidian.fs.GitignoreRecord|false>
  local records = {}

  ---@param base string
  ---@return obsidian.fs.GitignoreRecord?
  local function get_record(base)
    if records[base] == false then
      return nil
    elseif records[base] then
      return records[base]
    end

    local ignore_path = base == "" and vim.fs.joinpath(root, ".gitignore") or vim.fs.joinpath(root, base, ".gitignore")
    if not vim.uv.fs_stat(ignore_path) then
      records[base] = false
      return nil
    end

    ---@type obsidian.fs.GitignoreRecord?
    local record
    local parser = gitignore(vim.fn.readfile(ignore_path), { ignoreCase = true }, {
      type = function(path)
        return record and path == record.path and record.kind or "directory"
      end,
    })
    record = { path = "", kind = "file", parser = parser }
    records[base] = record
    return record
  end

  return function(relative_path, kind)
    local parts = vim.split(relative_path, "/", { plain = true })
    local ignored = false
    local base = ""

    -- A directory's own `.gitignore` applies to its children, not to the
    -- directory entry itself, hence the final path component is excluded.
    for i = 0, #parts - 1 do
      if i > 0 then
        base = table.concat(parts, "/", 1, i)
      end
      local record = get_record(base)
      if record then
        local local_path = table.concat(parts, "/", i + 1)
        record.path = local_path
        record.kind = kind
        local status = record.parser:status(vim.split(local_path, "/", { plain = true }))
        if status == "accepted" then
          ignored = true
        elseif status == "refused" then
          ignored = false
        end
      end
    end

    return ignored
  end
end

---@param root string
---@return boolean
local function is_in_vault(root)
  if not Obsidian or not Obsidian.dir then
    return false
  end
  root = vim.fs.normalize(root)
  local vault = vim.fs.normalize(tostring(Obsidian.dir))
  return root == vault or vim.startswith(root, vault .. "/")
end

---@param entry obsidian.fs.WalkEntry
---@param sort_by obsidian.config.SortBy|false
---@return string|integer
local function sort_value(entry, sort_by)
  if sort_by == "modified" then
    return entry.stat and entry.stat.mtime.sec or 0
  elseif sort_by == "accessed" then
    return entry.stat and entry.stat.atime.sec or 0
  elseif sort_by == "created" then
    local time = entry.stat and (entry.stat.birthtime or entry.stat.ctime)
    return time and time.sec or 0
  else
    return string.lower(entry.relative_path)
  end
end

---@param root string|obsidian.Path
---@param opts obsidian.fs.WalkOpts?
---@return fun(): obsidian.fs.WalkEntry?, boolean
---@return obsidian.config.SortBy|false
local function scanner(root, opts)
  opts = opts or {}
  ---@cast opts obsidian.fs.WalkOpts
  root = vim.fs.normalize(tostring(root))
  local is_gitignored = opts.gitignore == false and nil or gitignore_checker(root)
  local use_configured_ignores = opts.ignore ~= false and is_in_vault(root)
  local entry_type = opts.type or "file"
  local sort_by = opts.sort_by
  if sort_by == nil then
    sort_by = "path"
  end
  local needs_stat = opts.stat or sort_by == "modified" or sort_by == "accessed" or sort_by == "created"

  ---@param relative_path string
  ---@param kind string
  ---@return boolean
  local function ignored(relative_path, kind)
    if not opts.hidden and is_hidden(relative_path) then
      return true
    end
    if is_gitignored and is_gitignored(relative_path, kind) then
      return true
    end
    if type(opts.ignore) == "function" and opts.ignore(vim.fs.joinpath(root, relative_path), kind) then
      return true
    end
    if use_configured_ignores and ignore.is_ignored(vim.fs.joinpath(root, relative_path)) then
      return true
    end
    return false
  end

  local iterator = vim.fs.dir(root, {
    depth = opts.depth or 2147483647,
    skip = function(relative_dir)
      local path = vim.fs.joinpath(root, relative_dir)
      return not ignored(relative_dir, "directory") and not (opts.prune and opts.prune(path))
    end,
  })

  local function next_entry()
    local relative_path, kind = iterator()
    if relative_path == nil or kind == nil then
      return nil, true
    end
    if kind == entry_type and not ignored(relative_path, kind) then
      local path = vim.fs.joinpath(root, relative_path)
      if not opts.predicate or opts.predicate(path, kind) then
        local entry = {
          path = path,
          relative_path = relative_path,
          type = kind,
          stat = needs_stat and vim.uv.fs_stat(path) or nil,
        }
        return entry, false
      end
    end
    return nil, false
  end

  return next_entry, sort_by
end

---@param entries obsidian.fs.WalkEntry[]
---@param opts obsidian.fs.WalkOpts
---@param sort_by obsidian.config.SortBy|false
local function sort_entries(entries, opts, sort_by)
  if sort_by ~= false then
    table.sort(entries, function(a, b)
      local a_value = sort_value(a, sort_by)
      local b_value = sort_value(b, sort_by)
      if a_value == b_value then
        a_value = string.lower(a.relative_path)
        b_value = string.lower(b.relative_path)
      end
      if opts.sort_reversed then
        return a_value > b_value
      else
        return a_value < b_value
      end
    end)
  end
end

---@param root string|obsidian.Path
---@param opts obsidian.fs.WalkOpts?
---@return obsidian.fs.WalkEntry[]
local function collect(root, opts)
  opts = opts or {}
  local next_entry, sort_by = scanner(root, opts)
  local entries = {}
  while true do
    local entry, done = next_entry()
    if entry then
      entries[#entries + 1] = entry
    end
    if done then
      break
    end
  end
  sort_entries(entries, opts, sort_by)
  return entries
end

--- Iterate recursively over filesystem entries.
---
--- Paths are absolute and deterministic by default. Traversal respects hidden
--- files, the root `.gitignore`, and vault ignore filters unless disabled.
---
---@param root string|obsidian.Path
---@param opts obsidian.fs.WalkOpts?
---@return fun(): string?, string?, uv.fs_stat.result?
M.walk = function(root, opts)
  local entries = collect(root, opts)
  local i = 0
  return function()
    i = i + 1
    local entry = entries[i]
    if entry then
      return entry.path, entry.type, entry.stat
    end
  end
end

--- Collect paths returned by `walk()`.
---
---@param root string|obsidian.Path
---@param opts obsidian.fs.WalkOpts?
---@return string[]
M.find_files = function(root, opts)
  local paths = {}
  for path in M.walk(root, opts) do
    paths[#paths + 1] = path
  end
  return paths
end

--- Collect files without blocking the event loop for the whole traversal.
---
--- The scan is split into batches and the final callback receives the same
--- deterministically sorted result as `find_files()`.
---
---@param root string|obsidian.Path
---@param opts obsidian.fs.FindAsyncOpts?
---@param callback fun(paths: string[])
---@return fun() cancel
M.find_files_async = function(root, opts, callback)
  opts = opts or {}
  local next_entry, sort_by = scanner(root, opts)
  local entries = {}
  local batch_size = math.max(1, opts.batch_size or 200)
  local cancelled = false

  local function step()
    if cancelled then
      return
    end

    for _ = 1, batch_size do
      local entry, done = next_entry()
      if entry then
        entries[#entries + 1] = entry
      end
      if done then
        sort_entries(entries, opts, sort_by)
        callback(vim.tbl_map(function(item)
          return item.path
        end, entries))
        return
      end
    end

    vim.schedule(step)
  end

  vim.schedule(step)
  return function()
    cancelled = true
  end
end

--- Return an iterator over Markdown notes in a vault directory.
---
---@param dir string|obsidian.Path
---@return fun(): string?
M.dir = function(dir)
  local templates_dir
  local ok, api = pcall(require, "obsidian.api")
  if ok then
    templates_dir = api.templates_dir()
  end

  return M.walk(dir, {
    depth = 10,
    prune = templates_dir and function(path)
      return vim.fs.normalize(path) == vim.fs.normalize(tostring(templates_dir))
    end or nil,
    predicate = function(path)
      return vim.endswith(path, ".md") or vim.endswith(path, ".qmd") or vim.endswith(path, ".base")
    end,
    sort_by = false,
  })
end

return M
