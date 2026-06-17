local Path = require "obsidian.path"

local M = {}

---@return string|obsidian.Path|nil
local function default_path()
  if not (Obsidian and Obsidian.opts and Obsidian.opts.agenda and Obsidian.dir) then
    return nil
  end

  local file = Obsidian.opts.agenda.file or "agenda.md"
  local path = Path.new(file)
  if path:is_absolute() then
    return path
  end
  return Path.new(vim.fs.joinpath(tostring(Obsidian.dir), file))
end

---@param path string|obsidian.Path|nil
---@return string|nil
local function resolve_path(path)
  if not path then
    return nil
  end

  local resolved = Path.new(path)
  if not resolved:is_absolute() and Obsidian and Obsidian.dir then
    resolved = Path.new(Obsidian.dir) / tostring(path)
  end

  return tostring(resolved:resolve())
end

---Resolve an agenda item to a file-backed task location.
---
---Custom sources can set `item.path` (or `item.filename`) to override the
---default agenda file. If no path is present, the default agenda file is used.
---
---@param item obsidian.agenda.Item
---@param opts? obsidian.agenda.ResolveOpts
---@return obsidian.agenda.Item
M.resolve = function(item, opts)
  opts = opts or {}

  local path = item.path or item.filename or opts.default_path or default_path()
  item.path = resolve_path(path)
  item.filename = item.path

  if not item.lnum then
    item.lnum = 1
  end
  if not item.col then
    item.col = 1
  end

  return item
end

return M
