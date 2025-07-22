local Path = require "obsidian.path"
local abc = require "obsidian.abc"
local util = require "obsidian.util"
local config = require "obsidian.config"
local log = require "obsidian.log"

---@class obsidian.workspace.WorkspaceSpec
---
---@field path string|(fun(): string)
---@field name string|?
---@field strict boolean|? If true, the workspace root will be fixed to 'path' instead of the vault root (if different).
---@field overrides table|obsidian.config.ClientOpts|?

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
---@field overrides table|obsidian.config.ClientOpts|?
---@field locked boolean|?
local Workspace = abc.new_class {
  __tostring = function(self)
    return string.format("Workspace(name='%s', path='%s', root='%s')", self.name, self.path, self.root)
  end,
  __eq = function(a, b)
    local a_fields = a:as_tbl()
    a_fields.locked = nil
    local b_fields = b:as_tbl()
    b_fields.locked = nil
    return vim.deep_equal(a_fields, b_fields)
  end,
}

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
---@return obsidian.Workspace
Workspace.new = function(spec)
  spec = spec and spec or {}

  local path

  if type(spec.path) == "function" then
    path = spec.path()
  else
    path = spec.path
  end

  ---@cast path -function
  path = vim.fs.normalize(tostring(path))

  local self = Workspace.init()
  self.path = Path.new(path):resolve { strict = true }
  self.name = assert(spec.name or self.path.name)
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

  return self
end

--- Lock the workspace.
Workspace.lock = function(self)
  self.locked = true
end

--- Unlock the workspace.
Workspace._unlock = function(self)
  self.locked = false
end

--- Get the workspace corresponding to the directory (or a parent of), if there
--- is one.
---
---@param cur_dir string|obsidian.Path
---@param workspaces obsidian.workspace.WorkspaceSpec[]
---
---@return obsidian.Workspace|?
Workspace.get_workspace_for_dir = function(cur_dir, workspaces)
  local ok
  ok, cur_dir = pcall(function()
    return Path.new(cur_dir):resolve { strict = true }
  end)

  if not ok then
    return
  end

  for _, spec in ipairs(workspaces) do
    local w = Workspace.new(spec)
    if w.path == cur_dir or w.path:is_parent_of(cur_dir) then
      return w
    end
  end
end

--- 1. Set Obsidian.workspace, Obsidian.dir, and opts
--- 2. Make sure all the directories exists
--- 3. fire callbacks and exec autocmd event
---
---@param workspace obsidian.Workspace
---@param opts { lock: boolean|? }|?
Workspace.set = function(workspace, opts)
  opts = opts and opts or {}

  local dir = workspace.root
  local options = config.normalize(workspace.overrides, Obsidian._opts)

  Obsidian.workspace = workspace
  Obsidian.dir = dir
  Obsidian.opts = options

  -- Ensure directories exist.
  dir:mkdir { parents = true, exists_ok = true }

  if options.notes_subdir then
    (dir / options.notes_subdir):mkdir { parents = true, exists_ok = true }
  end

  if options.templates.folder then
    (dir / options.templates.folder):mkdir { parents = true, exists_ok = true }
  end

  if options.daily_notes.folder then
    (dir / options.daily_notes.folder):mkdir { parents = true, exists_ok = true }
  end

  if opts.lock then
    Obsidian.workspace:lock()
  end

  util.fire_callback("post_set_workspace", options.callbacks.post_set_workspace, workspace)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ObsidianWorkpspaceSet",
    data = { workspace = workspace },
  })
end

---@param workspace string name of workspace
---@param opts { lock: boolean|? }|?
Workspace.switch = function(workspace, opts)
  opts = opts and opts or {}

  if workspace == Obsidian.workspace.name then
    log.info("Already in workspace '%s' @ '%s'", workspace, Obsidian.workspace.path)
    return
  end

  for _, ws in ipairs(Obsidian.opts.workspaces) do
    if ws.name == workspace then
      return Workspace.set(Workspace.new(ws), opts)
    end
  end

  error(string.format("Workspace '%s' not found", workspace))
end

return Workspace
