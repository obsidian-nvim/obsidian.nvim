local Path = require "obsidian.path"
local util = require "obsidian.util"
local config = require "obsidian.config"
local log = require "obsidian.log"
local api = require "obsidian.api"

---@class obsidian.workspace.WorkspaceSpec
---
---@field path string|(fun(): string)|obsidian.Path|(fun(): obsidian.Path)
---@field name string|?
---@field strict boolean|? If true, the workspace root will be fixed to 'path' instead of the vault root (if different).
---@field overrides obsidian.config?

--- Each workspace represents a working directory (usually an Obsidian vault) along with
--- a set of configuration options specific to the workspace.
---
--- Workspaces are a little more general than Obsidian vaults as you can have a workspace
--- outside of a vault or as a subdirectory of a vault.
---
--- A workspace may be "unresolved" if its path does not yet exist or its dynamic path
--- function returned nil. Unresolved workspaces have `path = nil` and `root = nil` and
--- can be resolved later via `Workspace:resolve()`.
---
---@toc_entry obsidian.Workspace
---
---@class obsidian.Workspace
---
---@field name string An arbitrary name for the workspace.
---@field path obsidian.Path|? The normalized path to the workspace. Nil if unresolved.
---@field root obsidian.Path|? The normalized path to the vault root of the workspace. Nil if unresolved.
---@field overrides obsidian.config|?
---@field _resolve_path (fun(): string|obsidian.Path|nil)|? Stored dynamic path function for lazy re-evaluation.
---@field _strict boolean|? Stored strict flag for deferred root resolution.
local Workspace = {}
Workspace.__index = Workspace

Workspace.__tostring = function(self)
  local is_active = Obsidian.workspace and self.name == Obsidian.workspace.name
  local prefix = is_active and "*" or ""
  if self.path then
    return string.format("%s[%s] @ '%s'", prefix, self.name, self.path)
  else
    return string.format("%s[%s] (unresolved)", prefix, self.name)
  end
end

--- Find the vault root from a given directory.
---
--- This will traverse the directory tree upwards until a '.obsidian/' folder is found to
--- indicate the root of a vault, otherwise nil is returned.
---
---@param base_dir string|obsidian.Path
---
---@return obsidian.Path|?
Workspace.find_vault_root = function(base_dir)
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

--- Resolve a path and root for a workspace given a raw path value.
---
---@param raw_path string|obsidian.Path
---@param strict boolean|?
---
---@return obsidian.Path|?, obsidian.Path|?
local function resolve_path_and_root(raw_path, strict)
  local path = Path.new(vim.fs.normalize(tostring(raw_path)))

  if not path:exists() then
    return nil, nil
  end

  path = path:resolve { strict = true }

  local root
  if strict then
    root = path
  else
    root = Workspace.find_vault_root(path) or path
  end

  return path, root
end

--- Create a new 'Workspace' object.
---
--- Unlike before, this always returns a workspace object. If the path cannot be resolved
--- (function returned nil, or path does not exist), the workspace is created in an
--- "unresolved" state with `path = nil` and `root = nil`. Use `Workspace:resolve()` to
--- attempt resolution later.
---
---@param spec obsidian.workspace.WorkspaceSpec|?
---
---@return obsidian.Workspace
Workspace.new = function(spec)
  spec = spec and spec or {}

  local self = setmetatable({}, Workspace)
  self.overrides = spec.overrides
  self._strict = spec.strict or false

  -- Store the function for lazy re-evaluation if path is dynamic.
  if type(spec.path) == "function" then
    self._resolve_path = spec.path
  end

  -- Attempt eager resolution.
  local raw_path
  if self._resolve_path then
    raw_path = self._resolve_path()
  else
    raw_path = spec.path
  end

  if raw_path then
    local path, root = resolve_path_and_root(raw_path, self._strict)
    self.path = path
    self.root = root
  end

  -- Determine name: use spec.name, or derive from resolved path, or use a placeholder.
  if spec.name then
    self.name = spec.name
  elseif self.path then
    self.name = assert(self.path.name, ("failed to find a valid name for workspace %s"):format(tostring(self.path)))
  else
    -- Unresolved workspace without a name: use a placeholder.
    self.name = "(unnamed)"
  end

  return self
end

--- Check if this workspace has been resolved to a valid path.
---
---@return boolean
function Workspace:is_resolved()
  return self.path ~= nil
end

--- Attempt to resolve an unresolved workspace.
---
--- For dynamic workspaces (with a stored path function), this re-evaluates the function.
--- For static workspaces whose path didn't exist, this re-checks if the path now exists.
---
---@return boolean success Whether the workspace was successfully resolved.
function Workspace:resolve()
  if self:is_resolved() then
    return true
  end

  if not self._resolve_path then
    return false
  end

  local raw_path = self._resolve_path()
  if not raw_path then
    return false
  end

  local path, root = resolve_path_and_root(raw_path, self._strict)
  if not path then
    return false
  end

  self.path = path
  self.root = root

  -- Update name if it was a placeholder.
  if self.name == "(unnamed)" then
    self.name = self.path.name or self.name
  end

  return true
end

--- Auto-detect a vault by walking up from a directory looking for .obsidian/.
---
--- If the vault is already known in `Obsidian.workspaces`, returns the existing workspace.
--- Otherwise creates and returns a new ad-hoc workspace (but does NOT add it to the list;
--- the caller is responsible for that).
---
---@param dir string|obsidian.Path
---@return obsidian.Workspace|?
Workspace.detect = function(dir)
  local ok, resolved_dir = pcall(function()
    return Path.new(dir):resolve { strict = true }
  end)
  if not ok then
    return nil
  end

  local vault_root = Workspace.find_vault_root(resolved_dir)
  if not vault_root then
    return nil
  end

  vault_root = vault_root:resolve { strict = true }

  -- Check if this vault is already a known resolved workspace.
  if Obsidian.workspaces then
    for _, ws in ipairs(Obsidian.workspaces) do
      if ws:is_resolved() and ws.root == vault_root then
        return ws
      end
    end
  end

  -- Create a new ad-hoc workspace.
  return setmetatable({
    name = vault_root.name or tostring(vault_root),
    path = vault_root,
    root = vault_root,
    overrides = nil,
    _resolve_path = nil,
    _strict = false,
  }, Workspace)
end

--- Set the current workspace.
--- 1. Set Obsidian.workspace, Obsidian.dir, and opts
--- 2. Make sure all the directories exist
--- 3. Fire callbacks and exec autocmd event
---
--- The workspace must be resolved before calling this.
---
---@param workspace obsidian.Workspace | string
Workspace.set = function(workspace)
  if type(workspace) == "string" then
    if Obsidian.workspace and workspace == Obsidian.workspace.name then
      log.info("Already in workspace '%s' @ '%s'", workspace, Obsidian.workspace.path)
      return
    end

    for _, ws in ipairs(Obsidian.workspaces) do
      if ws.name == workspace then
        if not ws:is_resolved() then
          if not ws:resolve() then
            error(string.format("Workspace '%s' could not be resolved", workspace))
          end
        end
        return Workspace.set(ws)
      end
    end

    error(string.format("Workspace '%s' not found", workspace))
  end

  assert(workspace:is_resolved(), string.format("Cannot set unresolved workspace '%s'", workspace.name))

  local dir = workspace.root
  local options = config.normalize(workspace.overrides or {}, Obsidian._opts)

  Obsidian.workspace = workspace
  Obsidian.dir = dir
  Obsidian.opts = options

  -- Ensure directories exist.
  dir:mkdir { parents = true }

  if options.notes_subdir ~= nil then
    (dir / options.notes_subdir):mkdir { parents = true }
  end

  if options.templates.enabled and options.templates.folder then
    (dir / options.templates.folder):mkdir { parents = true }
  end

  if options.daily_notes.enabled and options.daily_notes.folder then
    (dir / options.daily_notes.folder):mkdir { parents = true }
  end

  -- Setup UI add-ons.
  local has_no_renderer = not (api.get_plugin_info "render-markdown.nvim" or api.get_plugin_info "markview.nvim")
  if has_no_renderer and (options.ui.enable or options.ui.enabled) then
    require("obsidian.ui").setup(workspace, options.ui)
  end

  util.fire_callback("post_set_workspace", options.callbacks.post_set_workspace, workspace)

  vim.api.nvim_exec_autocmds("User", {
    pattern = "ObsidianWorkpspaceSet",
    data = { workspace = workspace },
  })
end

---Resolve a directory to a resolved workspace that it belongs to.
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
    if ws:is_resolved() and (ws.path == dir or ws.path:is_parent_of(dir)) then
      return ws
    end
  end
end

--- 1. Create workspace objects from user input specs (resolved or unresolved)
--- 2. Warn about any workspaces that could not be resolved
--- 3. Set current workspace based on cwd, or the order of specs (if any resolved)
---
---@param specs obsidian.workspace.WorkspaceSpec[]
---@return obsidian.Workspace[]
Workspace.setup = function(specs)
  local workspaces = {}

  for _, spec in ipairs(specs) do
    local ws = Workspace.new(spec)
    table.insert(workspaces, ws)

    if not ws:is_resolved() then
      if ws._resolve_path then
        log.warn(
          "Workspace '%s' could not be resolved (dynamic path returned nil). "
            .. "It will be re-evaluated when entering a buffer.",
          ws.name
        )
      else
        log.warn(
          "Workspace '%s' at path '%s' could not be resolved (path does not exist).",
          ws.name,
          tostring(spec.path)
        )
      end
    end
  end

  Obsidian.workspaces = workspaces
  Obsidian.workspace = nil
  Obsidian.dir = nil

  -- Find resolved workspaces to determine the current one.
  local resolved = vim.tbl_filter(function(ws)
    return ws:is_resolved()
  end, workspaces)

  if vim.tbl_isempty(resolved) then
    log.info "No workspaces could be resolved at startup. Workspace will be set when entering a buffer."
    return workspaces
  end

  local current_workspace = Workspace.find(assert(vim.uv.cwd()), resolved)

  if current_workspace then
    Workspace.set(current_workspace)
  else
    Workspace.set(resolved[1])
  end

  return workspaces
end

return Workspace
