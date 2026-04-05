local api = require "obsidian.api"
local log = require "obsidian.log"
local client = require "obsidian.sync.client"

--- Connect a workspace to a chosen remote vault, apply sync config, and optionally start syncing.
---@param remote obsidian.sync.RemoteVault
---@param workspace obsidian.Workspace
local function connect_and_configure(remote, workspace)
  local path = tostring(workspace.root)

  local out = client.setup(remote.hash, path)
  if not out or out.code ~= 0 then
    return
  end

  -- Apply sync settings from user config.
  if Obsidian.opts.sync then
    client.apply_config(path, Obsidian.opts.sync)
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

  local remote_create_result = client.create_remote(name)

  if not remote_create_result then
    log.err "Failed to parse the newly created remote vault ID."
    return
  end

  connect_and_configure({ hash = remote_create_result.hash, name = name }, workspace)
end

local CREATE_NEW = { hash = "", name = "" }

--- Prompt the user to select (or create) a remote vault, then connect the workspace to it.
---@param workspace obsidian.Workspace
---@param remotes obsidian.sync.RemoteVault[] list of remote vaults to choose from
---@param local_vaults table<string, obsidian.sync.LocalVault>? pre-fetched local vaults
local function select_remote(workspace, remotes, local_vaults)
  local sync = require "obsidian.sync"
  -- Already configured check.
  if sync.is_configured(workspace, local_vaults) then
    log.info("Workspace '%s' is already linked to a remote vault.", workspace.name)
    return
  end

  if #remotes == 0 then
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
---@param local_vaults table<string, obsidian.sync.LocalVault> map of path -> local vault info (id at least)
---@param remotes obsidian.sync.RemoteVault[] list of remote vaults
---@return table<string, string> map of path -> remote name (or id if name unknown)
local function build_linked_map(local_vaults, remotes)
  local remote_by_id = {}
  if remotes then
    for _, r in ipairs(remotes) do
      remote_by_id[r.hash] = r.name
    end
  end

  local map = {}
  for vault_path, vault in pairs(local_vaults) do
    map[vault_path] = remote_by_id[vault.hash] or vault.hash
  end
  return map
end

local function setup()
  local workspaces = Obsidian.workspaces
  if not workspaces or #workspaces == 0 then
    log.err "No workspaces configured."
    return
  end

  local local_vaults = client.list_local()
  local remotes = client.list_remote()

  local linked = build_linked_map(local_vaults, remotes)

  if #workspaces == 1 then
    select_remote(workspaces[1], remotes, local_vaults)
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
      select_remote(ws, remotes, local_vaults)
    end
  end)
end

local function unlink()
  local workspaces = Obsidian.workspaces
  if not workspaces or #workspaces == 0 then
    log.err "No workspaces configured."
    return
  end

  local local_vaults = client.list_local()
  local remotes = client.list_remote()

  local linked = build_linked_map(local_vaults, remotes)

  local vaults_with_remotes = vim.tbl_filter(function(ws)
    local root = tostring(ws.root)
    return linked[root] ~= nil
  end, workspaces)

  vim.ui.select(vaults_with_remotes, {
    prompt = "Select workspace to unlink",
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
      client.stop(tostring(ws.root))
      client.unlink(tostring(ws.root))
    end
  end)
end

return {
  setup = setup,
  unlink = unlink,
}
