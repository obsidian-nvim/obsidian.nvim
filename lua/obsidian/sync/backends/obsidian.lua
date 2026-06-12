local api = require "obsidian.api"
local log = require "obsidian.log"
local client = require "obsidian.sync.client"
local runner = require "obsidian.sync.runner"
local status = require "obsidian.sync.status"

local M = {
  name = "obsidian",
  caps = { remote_catalog = true },
}

---@param ws obsidian.Workspace
---@param vaults table<string, obsidian.sync.LocalVault>?
---@return boolean
function M.is_configured(ws, vaults)
  vaults = vaults or client.list_local()
  if not vaults then
    return false
  end
  return vaults[tostring(ws.root)] ~= nil
end

---@param dir string
---@param opts { silent: boolean? }?
function M.start(dir, opts)
  opts = opts or {}
  local handler = runner.make_handler(dir)

  if not client.cli then
    log.err "CLI not available, cannot start sync."
    return
  end

  if runner.procs[dir] ~= nil then
    if not opts.silent then
      log.info("Sync already running for %s", dir)
    end
    return
  end

  local callback = function(out)
    if out.code ~= 0 then
      log.err("obsidian sync exited %s", out.stderr)
      runner.append_log(dir, string.format("obsidian sync exited with code %s: %s", out.code, out.stderr))
    end
  end

  client.set_config(dir, Obsidian.opts.sync)

  runner.procs[dir] = client.run_async("sync", { continuous = true }, {
    cwd = dir,
    stderr = handler,
    stdout = handler,
  }, callback, { silent = opts.silent })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("obsidian-sync-" .. dir, { clear = true }),
    callback = function()
      M.pause(dir)
    end,
  })
end

---@param dir string
---@return boolean?, string?
function M.pause(dir)
  if not runner.procs[dir] then
    status.set "paused"
    return true
  end

  local ok, err = pcall(function()
    runner.procs[dir]:kill(15)
    runner.procs[dir] = nil
    status.set "paused"
  end)
  return ok, err
end

---@param dir string
---@param opts { silent: boolean? }?
function M.sync_once(dir, opts)
  opts = opts or {}
  local handler = runner.make_handler(dir)

  if not client.cli then
    if not opts.silent then
      log.err "CLI not available, cannot run sync."
    end
    return
  end

  if runner.procs[dir] ~= nil then
    if not opts.silent then
      log.info("Continuous sync already running for %s; one-shot skipped", dir)
    end
    return
  end

  client.set_config(dir, Obsidian.opts.sync)

  client.run_async("sync", {}, {
    cwd = dir,
    stderr = handler,
    stdout = handler,
  }, function(out)
    if out.code ~= 0 then
      runner.append_log(dir, string.format("obsidian sync exited with code %s: %s", out.code, out.stderr))
    else
      runner.append_log(dir, "Fully synced")
    end
  end, { silent = opts.silent })
end

---@param dir string
function M.log(dir)
  runner.open_log_buf(dir)
end

---------------
--- Wizard ---
---------------

---@param remote obsidian.sync.RemoteVault
---@param workspace obsidian.Workspace
---@param setup_opts { password?: string, prompt_password?: boolean }?
local function connect_and_configure(remote, workspace, setup_opts)
  local path = tostring(workspace.root)

  local out = client.setup(remote.hash, path, setup_opts)
  if not out or out.code ~= 0 then
    return
  end

  if Obsidian.opts.sync then
    client.set_config(path, Obsidian.opts.sync)
  end

  if api.confirm "Start syncing now?" == "Yes" then
    require("obsidian.sync").start(workspace)
  end
end

---@param workspace obsidian.Workspace
local function create_and_connect(workspace)
  local name = api.input "New remote vault name"
  if not name or name == "" then
    return
  end

  local password = vim.fn.inputsecret "End-to-end encryption password (leave empty for managed encryption): "
  local create_opts = {}
  local setup_opts = {}
  if password and password ~= "" then
    create_opts.encryption = "e2ee"
    create_opts.password = password
    setup_opts.password = password
  else
    create_opts.encryption = "standard"
  end

  local remote_create_result = client.create_remote(name, create_opts)

  if not remote_create_result then
    log.err "Failed to create remote vault."
    return
  end

  connect_and_configure(remote_create_result, workspace, setup_opts)
end

local CREATE_NEW = { hash = "", name = "" }

---@param workspace obsidian.Workspace
---@param remotes obsidian.sync.RemoteVault[]
---@param local_vaults table<string, obsidian.sync.LocalVault>?
local function select_remote(workspace, remotes, local_vaults)
  if M.is_configured(workspace, local_vaults) then
    log.info("Workspace '%s' is already linked to a remote vault.", workspace.name)
    return
  end

  if #remotes == 0 then
    if api.confirm "No remote vaults found. Create one now?" == "Yes" then
      create_and_connect(workspace)
    end
    return
  end

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

---@param workspace obsidian.Workspace
function M.setup(workspace)
  local local_vaults = client.list_local(false)
  local remotes = client.list_remote(false)
  select_remote(workspace, remotes, local_vaults)
end

---@param workspace obsidian.Workspace
function M.disconnect(workspace)
  local dir = tostring(workspace.root)
  M.pause(dir)
  client.unlink(dir)
end

--- Build a lookup from workspace root path -> remote vault name.
---@param local_vaults table<string, obsidian.sync.LocalVault>
---@param remotes obsidian.sync.RemoteVault[]
---@return table<string, string>
function M.build_linked_map(local_vaults, remotes)
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

---@param ws obsidian.Workspace
---@return string
function M.ws_formatter(ws)
  local linked = M.build_linked_map(client.list_local(), client.list_remote())
  local root = tostring(ws.root)
  local remote_name = linked[root]
  if remote_name then
    return string.format("%s (%s) -> %s", ws.name, root, remote_name)
  end
  return string.format("%s (%s)", ws.name, root)
end

return M
