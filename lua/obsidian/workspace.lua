local Path = require "obsidian.path"
local util = require "obsidian.util"
local config = require "obsidian.config"
local log = require "obsidian.log"

--- Each workspace represents a working directory (usually an Obsidian vault) along with
--- a set of configuration options specific to the workspace.
---
--- Workspaces are a little more general than Obsidian vaults as you can have a workspace
--- outside of a vault or as a subdirectory of a vault.
---
---@toc_entry obsidian.Workspace
---
---@class obsidian.Workspace : obsidian.ABC
---
---@field name string An arbitrary name for the workspace.
---@field path obsidian.Path The normalized path to the workspace.
---@field root obsidian.Path The normalized path to the vault root of the workspace. This usually matches 'path'.
---@field overrides obsidian.config|?
local Workspace = {}
Workspace.__index = Workspace

Workspace.__tostring = function(self)
  if self.name == Obsidian.workspace.name then
    return string.format("*[%s] @ '%s'", self.name, self.path)
  end
  return string.format("[%s] @ '%s'", self.name, self.path)
end

--- Find the vault root from a given directory.
---
--- This will traverse the directory tree upwards until a '.obsidian/' folder is found to
--- indicate the root of a vault, otherwise the given directory is used as-is.
---
---@param base_dir string|obsidian.Path
---
---@return obsidian.Path|?
local function find_vault_root(base_dir)
  local vault_indicator_folder = ".obsidian"
  base_dir = Path.new(base_dir)
  local dirs = Path.new(base_dir):parents()
  table.insert(dirs, 1, base_dir)

  for _, dir in ipairs(dirs) do
    local maybe_vault = dir / vault_indicator_folder
    if maybe_vault:is_dir() then
      return dir
    end
  end

  return nil
end

--- Create a new 'Workspace' object. This assumes the workspace already exists on the filesystem.
---
---@param spec obsidian.workspace.WorkspaceSpec|?
---
---@return obsidian.Workspace?
Workspace.new = function(spec)
  spec = spec and spec or {}

  local path

  if type(spec.path) == "function" then
    path = spec.path()
    if not path then
      return
    end
  else
    path = spec.path
  end

  ---@cast path -function
  path = vim.fs.normalize(tostring(path))
  path = Path.new(path)

  if not path:exists() then
    return
  end

  local self = {}
  self.path = path:resolve { strict = true }
  self.name =
    assert(spec.name or self.path.name, ("failed to find a valid name for workspace %s"):format(tostring(self.path)))
  self.overrides = spec.overrides

  if spec.strict then
    self.root = self.path
  else
    local vault_root = find_vault_root(self.path)
    if vault_root then
      self.root = vault_root
    else
      self.root = self.path
    end
  end

  return setmetatable(self, Workspace)
end

--- Set the current workspace
--- 1. Set Obsidian.workspace, Obsidian.dir, and opts
--- 2. Make sure all the directories exists
--- 3. fire callbacks and exec autocmd event
---
---@param workspace obsidian.Workspace | string
Workspace.set = function(workspace)
  if type(workspace) == "string" then
    if workspace == Obsidian.workspace.name then
      log.info("Already in workspace '%s' @ '%s'", workspace, Obsidian.workspace.path)
      return
    end

    for _, ws in ipairs(Obsidian.workspaces) do
      if ws.name == workspace then
        return Workspace.set(ws)
      end
    end

    error(string.format("Workspace '%s' not found", workspace))
  end

  local dir = workspace.root
  local options = config.normalize(workspace.overrides, Obsidian._opts)

  Obsidian.workspace = workspace
  Obsidian.dir = dir
  Obsidian.opts = options

  -- Ensure directories exist.
  dir:mkdir { parents = true }

  if options.notes_subdir then
    (dir / options.notes_subdir):mkdir { parents = true }
  end

  if options.templates.folder then
    (dir / options.templates.folder):mkdir { parents = true }
  end

  if options.daily_notes.folder then
    (dir / options.daily_notes.folder):mkdir { parents = true }
  end

  util.fire_callback("post_set_workspace", options.callbacks.post_set_workspace, workspace)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ObsidianWorkpspaceSet",
    data = { workspace = workspace },
  })
end

---Resolve a directory to a workspace that it belongs to.
---
---@param dir string|obsidian.Path
---@param workspaces obsidian.Workspace[]
---
---@return obsidian.Workspace|?
Workspace.find = function(dir, workspaces)
  local ok
  ok, dir = pcall(function()
    return Path.new(dir):resolve { strict = true }
  end)

  if not ok then
    return
  end

  for _, ws in ipairs(workspaces) do
    if ws.path == dir or ws.path:is_parent_of(dir) then
      return ws
    end
  end
end

--- 1. Resolve and return all the workspaces from user input specs
--- 2. Set current workspace based on cwd, or the order of specs
---@param specs obsidian.workspace.WorkspaceSpec[]
---@return obsidian.Workspace[]
Workspace.setup = function(specs)
  local workspaces = {}

  for _, spec in ipairs(specs) do
    local ws = Workspace.new(spec)
    if ws then
      table.insert(workspaces, ws)
    end
  end

  if vim.tbl_isempty(workspaces) then
    error "At least one workspace is required!\nPlease specify a valid workspace"
  end

  local current_workspace = Workspace.find(assert(vim.uv.cwd()), workspaces)

  if current_workspace then
    Workspace.set(current_workspace)
  else
    Workspace.set(workspaces[1])
  end

  Obsidian.workspaces = workspaces

  return workspaces
end

return Workspace
