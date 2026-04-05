local api = require "obsidian.api"
local log = require "obsidian.log"
local sync = require "obsidian.sync.client"

--- Connect a workspace to a chosen remote vault, apply sync config, and optionally start syncing.
---@param remote { hash: string, name: string }
---@param workspace obsidian.Workspace
local function connect_and_configure(remote, workspace)
  local path = tostring(workspace.root)

  local out = sync.setup_sync(remote.hash, path)
  if not out or out.code ~= 0 then
    return
  end

  -- Apply sync settings from user config.
  if Obsidian.opts.sync then -- TODO:
    sync.apply_config(path, Obsidian.opts.sync)
  end

  if api.confirm "Start syncing now?" == "Yes" then
    require("obsidian.sync").start(workspace)
  end
end

--- Prompt to create a new remote vault, then connect the workspace to it.
---@param workspace obsidian.Workspace
local function create_and_connect(workspace)
  local name = api.input "New remote vault name"
  if not name or name == "" then
    return
  end

  local out = sync.create_remote_sync(name)
  if not out or out.code ~= 0 then
    return
  end

  -- Re-list to get the newly created vault's hash.
  local remotes = sync.list_remote()
  if not remotes or #remotes == 0 then
    log.err "Failed to find the newly created remote vault."
    return
  end

  -- Auto-select the vault matching the name we just created.
  local created = vim.iter(remotes):find(function(r)
    return r.name == name
  end)
  if created then
    connect_and_configure(created, workspace)
  else
    -- Fallback: if name matching fails (e.g. server trimmed it), use the last one.
    connect_and_configure(remotes[#remotes], workspace)
  end
end

local CREATE_NEW = { hash = "", name = "" }

--- Prompt the user to select (or create) a remote vault, then connect the workspace to it.
---@param workspace obsidian.Workspace
local function select_remote(workspace)
  local path = tostring(workspace.root)

  -- Already configured check.
  if sync.is_configured(path) then
    log.info("Workspace '%s' is already linked to a remote vault.", workspace.name)
    return
  end

  -- list_remote triggers auto-login on exit code 2 via run_sync.
  local remotes = sync.list_remote()

  if not remotes or #remotes == 0 then
    create_and_connect(workspace)
    return
  end

  -- Append a "Create new remote" sentinel at the end.
  local items = vim.list_extend(vim.deepcopy(remotes), { CREATE_NEW })

  vim.ui.select(items, {
    prompt = "Select remote vault to sync with",
    format_item = function(item)
      if item == CREATE_NEW then
        return "+ Create new remote"
      end
      return item.name
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice == CREATE_NEW then
      create_and_connect(workspace)
    else
      connect_and_configure(choice, workspace)
    end
  end)
end

--- Build a lookup from workspace root path -> remote vault name.
---@return table<string, string> map of path -> remote name (or id if name unknown)
local function build_linked_map()
  local local_vaults = sync.list_local()
  if not local_vaults then
    return {}
  end

  local remotes = sync.list_remote()
  local remote_by_id = {}
  if remotes then
    for _, r in ipairs(remotes) do
      remote_by_id[r.hash] = r.name
    end
  end

  local map = {}
  for vault_path, vault in pairs(local_vaults) do
    map[vault_path] = remote_by_id[vault.id] or vault.id
  end
  return map
end

local function wizard()
  if not sync or not sync.check_installed() then
    log.err "obsidian-headless not found. Install with: npm install -g obsidian-headless"
    return
  end

  local workspaces = Obsidian.workspaces
  if not workspaces or #workspaces == 0 then
    log.err "No workspaces configured."
    return
  end

  local linked = build_linked_map()

  if #workspaces == 1 then
    select_remote(workspaces[1])
    return
  end

  vim.ui.select(workspaces, {
    prompt = "Select workspace to set up sync for",
    format_item = function(ws)
      local root = tostring(ws.root)
      local remote_name = linked[root]
      if remote_name ~= nil then
        return string.format("%s (%s) -> %s", ws.name, root, remote_name)
      end
      return string.format("%s (%s)", ws.name, root)
    end,
  }, function(ws)
    if ws then
      select_remote(ws)
    end
  end)
end

return {
  wizard = wizard,
}
