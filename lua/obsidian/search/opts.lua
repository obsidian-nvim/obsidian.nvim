local api = require "obsidian.api"
local fs_util = require "obsidian.util.fs"

local M = {}

---@param query string
---@return boolean
M.should_ignore_case = function(query)
  return vim.o.ignorecase and (not vim.o.smartcase or query:find "%u" == nil)
end

---@param opts obsidian.search.BackendOpts
---@param path string
local function add_exclude(opts, path)
  opts.exclude = opts.exclude or {}
  if not vim.tbl_contains(opts.exclude, path) then
    opts.exclude[#opts.exclude + 1] = path
  end
end

---Resolve workspace search defaults and exclusions into concrete backend options.
---@param dir string|obsidian.Path
---@param opts obsidian.search.BackendOpts|?
---@return obsidian.search.BackendOpts
M.resolve = function(dir, opts)
  opts = vim.deepcopy(opts or {})

  local workspace = Obsidian and api.find_workspace(dir) or nil
  local workspace_opts = {}
  if workspace then
    workspace_opts = api._workspace_opts(workspace)
  elseif Obsidian and Obsidian.workspaces == nil then
    -- Keep compatibility with callers that provide the legacy state shape.
    workspace_opts = Obsidian.opts or {}
  end
  local search_opts = workspace_opts.search or {}

  if opts.sort_by == nil then
    opts.sort_by = search_opts.sort_by
  end
  if opts.sort_reversed == nil then
    opts.sort_reversed = search_opts.sort_reversed
  end

  local templates_dir = workspace and api.templates_dir(workspace) or nil
  if templates_dir ~= nil then
    local relative = fs_util.relpath(tostring(dir), tostring(templates_dir))
    if relative == "." then
      add_exclude(opts, "**")
    elseif relative ~= nil and not vim.startswith(relative, "..") then
      add_exclude(opts, relative)
    end
  elseif workspace_opts.templates and workspace_opts.templates.folder then
    add_exclude(opts, tostring(workspace_opts.templates.folder))
  end

  local ignore_filters = workspace_opts.file and workspace_opts.file.ignore_filters or {}
  for _, pattern in ipairs(ignore_filters) do
    add_exclude(opts, pattern)
  end

  return opts
end

return M
