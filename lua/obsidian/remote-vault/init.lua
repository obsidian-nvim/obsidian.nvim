local commands = require "obsidian.commands"
local fs_util = require "obsidian.util.fs"
local log = require "obsidian.log"
local picker = require "obsidian.picker"
local Sync = require "obsidian.remote-vault.sync"
local Vault = require("obsidian.remote-vault.vault").Vault
local Workspace = require "obsidian.workspace"

local M = {}

---@type table<string, obsidian.remote_vault.Vault>
local registered = {}
---@type table<string, boolean>
local running = {}
local command_installed = false

local function names()
  local out = vim.tbl_keys(registered)
  table.sort(out)
  return out
end

local function emit(pattern, data)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = pattern, data = data })
  if not ok then
    log.warn("Remote vault event %s failed: %s", pattern, err)
  end
end

local function log_report(report)
  local message = string.format(
    "Remote vault %s: %d created, %d updated, %d unchanged, %d archived, %d deleted, %d kept",
    report.name,
    #report.created,
    #report.updated,
    #report.plan.unchanged,
    #report.archived,
    #report.deleted,
    #report.kept
  )
  if #report.errors > 0 then
    log.err("%s; %d error(s): %s", message, #report.errors, table.concat(report.errors, "; "))
  else
    log.info(message)
  end
end

---@param name string
---@param opts? { force: boolean?, dry_run: boolean? }
---@param on_finish? fun(err: string?, report: obsidian.remote_vault.Report?)
---@return table? task
function M.sync(name, opts, on_finish)
  local vault = registered[name]
  if not vault then
    error(string.format("unknown remote vault %q", name), 2)
  elseif running[name] then
    error(string.format("remote vault %q is already syncing", name), 2)
  end

  running[name] = true
  emit("ObsidianRemoteVaultSyncStart", { name = name })
  local ok, task_or_err = pcall(Sync.run, vault, opts, function(err, report)
    running[name] = nil
    if err then
      emit("ObsidianRemoteVaultSyncError", { name = name, error = err })
    else
      local completed = assert(report, "remote vault sync completed without a report")
      emit("ObsidianRemoteVaultSyncComplete", {
        name = name,
        created = #completed.created,
        updated = #completed.updated,
        unchanged = #completed.plan.unchanged,
        archived = #completed.archived,
        deleted = #completed.deleted,
        kept = #completed.kept,
        errors = vim.deepcopy(completed.errors),
      })
    end
    if on_finish then
      on_finish(err, report)
    elseif err then
      log.err("Remote vault %s failed: %s", name, err)
    else
      log_report(assert(report, "remote vault sync completed without a report"))
    end
  end)
  if not ok then
    running[name] = nil
    error(task_or_err, 2)
  end
  return task_or_err
end

---@param vault obsidian.remote_vault.Vault
local function inject_workspace(vault)
  local state = Obsidian
  if not state or not state.workspaces then
    error("remote vaults must be registered after obsidian.nvim setup", 3)
  end

  local remote_path = tostring(vault.path:resolve())
  for _, workspace in ipairs(state.workspaces) do
    local workspace_path = tostring(workspace.root:resolve())
    if workspace.name == vault.name then
      error(string.format("workspace name %q is already registered", vault.name), 3)
    elseif fs_util.is_subpath(remote_path, workspace_path) or fs_util.is_subpath(workspace_path, remote_path) then
      error(string.format("remote vault %q overlaps workspace %q", remote_path, workspace_path), 3)
    end
  end

  vault.path:mkdir { parents = true }
  local workspace = assert(
    Workspace.new {
      path = vault.path,
      name = vault.name,
      strict = true,
    },
    "failed to create workspace for remote vault " .. vault.name
  )
  state.workspaces[#state.workspaces + 1] = workspace
  vault.workspace = workspace
end

---@param vault obsidian.remote_vault.Spec|obsidian.remote_vault.Vault
---@return obsidian.remote_vault.Vault
function M.register(vault)
  ---@type obsidian.remote_vault.Vault
  local normalized
  if getmetatable(vault) == Vault then
    normalized = vault --[[@as obsidian.remote_vault.Vault]]
  else
    normalized = Vault.new(vault --[[@as obsidian.remote_vault.Spec]])
  end
  ---@cast normalized obsidian.remote_vault.Vault
  if registered[normalized.name] then
    error(string.format("remote vault %q is already registered", normalized.name), 2)
  end
  inject_workspace(normalized)
  registered[normalized.name] = normalized
  return normalized
end

---@param name string
---@return obsidian.remote_vault.Vault?
function M.get(name)
  return registered[name]
end

---@return string[]
function M.names()
  return names()
end

local function select_vault(callback)
  picker.select(names(), { prompt = "Remote vault" }, function(items)
    if items[1] then
      callback(items[1])
    end
  end)
end

local function command(data)
  local action, name = data.fargs[1], data.fargs[2]
  if action ~= "sync" or #data.fargs > 2 then
    log.err "Usage: Obsidian remote sync [name]"
    return
  end
  if name then
    local ok, err = pcall(M.sync, name)
    if not ok then
      log.err("%s", err)
    end
  else
    select_vault(function(selected)
      M.sync(selected)
    end)
  end
end

local function complete(arg_lead, cmdline)
  if cmdline:match "%sremote%s+%S*$" then
    return vim.tbl_filter(function(value)
      return vim.startswith(value, arg_lead)
    end, { "sync" })
  elseif cmdline:match "%sremote%s+sync%s+%S*$" then
    return vim.tbl_filter(function(value)
      return vim.startswith(value, arg_lead)
    end, names())
  end
  return {}
end

local function install_command()
  if command_installed then
    return
  end
  commands.register("remote", { nargs = "*", func = command, complete = complete })
  command_installed = true
end

---@param opts? { vaults?: (obsidian.remote_vault.Spec|obsidian.remote_vault.Vault)[] }
function M.setup(opts)
  local vaults = opts and opts.vaults or {}
  for _, vault in ipairs(vaults) do
    M.register(vault)
  end
  install_command()
end

M.Vault = Vault
M.plan = Sync.plan
M.adapters = {
  feed = require "obsidian.remote-vault.adapters.feed",
  github = require "obsidian.remote-vault.adapters.github",
}

return M
