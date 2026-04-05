local cli = require "obsidian.cli"
local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}

local function get_plugin_root()
  local root = vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
    return vim.endswith(path, "obsidian.nvim")
  end)
  return root
end

---@return string?
function M.get_cmd()
  local plugin_root = get_plugin_root()
  local cmd
  if plugin_root then
    local local_bin = vim.fs.joinpath(plugin_root, "node_modules", ".bin", "ob")
    if vim.fn.executable(local_bin) == 1 then
      cmd = local_bin
    end
  end

  if not cmd and vim.fn.executable "ob" == 1 then
    cmd = "ob"
  end

  return cmd
end

---@return boolean
---@return string?
local function install_local_cli()
  local plugin_root = get_plugin_root()
  if not plugin_root then
    log.err "Could not find plugin root, cannot install CLI."
    return false
  end

  local cmds = { "npm", "install", "obsidian-headless" }

  local result = vim.system(cmds, { cwd = plugin_root }):wait()
  if result.code ~= 0 then
    log.err("Failed to install obsidian-headless: %s", result)
    return false
  else
    local new_cmd = M.cmd
    log.info "obsidian-headless installed successfully!"
    return true, new_cmd
  end
end

local state = {
  cli = (function()
    local cmd = M.cmd
    if cmd then
      return cli.new(cmd, {})
    else
      if api.confirm "Obsidian CLI not found. Would you like to install it locally for obsidian.nvim?" == "Yes" then
        local success, new_cmd = install_local_cli()
        if success and new_cmd then
          return cli.new(new_cmd, {})
        else
          log.err "CLI still not found after installation. Please report issue to repo."
          return nil
        end
      end
    end
  end)(),
}

local cmd

setmetatable(M, {
  __index = function(_, k)
    if k == "cmd" then
      if not cmd then
        return M.get_cmd()
      else
        return cmd
      end
    else
      return rawget(M, k)
    end
  end,
})

function M.run_sync(subcmd, flags, opts)
  if not state.cli then
    log.err "CLI not initialized, cannot run command."
    return nil
  end

  local out = state.cli:run_sync(subcmd, flags, opts)
  if out.code == 2 then
    if api.confirm "Not login in, login to your obsidian account?" == "Yes" then
      M.login_sync()
      return state.cli:run_sync(subcmd, flags, opts)
    end
    return
  end
  return out
end

function M.run(subcmd, flags, opts)
  if not state.cli then
    log.err "CLI not initialized, cannot run command."
    return nil
  end

  return state.cli:run(subcmd, flags, opts)
end

---@param email string|?
---@param password string|?
function M.login_sync(email, password)
  email = email or api.input "Email"
  password = password or vim.fn.inputsecret "Password: "

  if not email or not password then
    log.err "Email and password are required for login."
    return
  end

  local out = M.run_sync("login", { email = email, password = password }, {})

  if out ~= nil and out.code == 0 then
    log.info "Login successful!"
  else
    log.err("Login failed: %s", out and out.stderr)
  end
  return out
end

function M.logout()
  M.run("logout", {}, {
    callback = function(out)
      if out.code == 0 then
        log.info "Logout successful!"
      else
        log.err("Logout failed: %s", out.stderr)
      end
    end,
  })
end

---@return { hash: string, name: string }[]  -- list of remote vaults
function M.list_remote()
  local out = M.run_sync("sync-list-remote", {}, { silent = true })

  if not out or not out.stdout then
    return {}
  end

  local lines = vim.split(out.stdout, "\n", { trimempty = true })
  local pat = "^%s*([0-9a-fA-F]+)%s+([^\n]+)"

  local res = {}
  for _, line in ipairs(lines) do
    local hash, name = line:match(pat)
    if hash and name then
      table.insert(res, { hash = hash, name = name })
    end
  end

  return res
end

---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws)
  local vaults = M.list_local()
  if not vaults then
    return false
  end
  return vaults[tostring(ws.root)] ~= nil
end

---@param vault string  -- vault id or name
---@param path string
---@return vim.SystemCompleted|nil
function M.setup(vault, path)
  local out = M.run_sync("sync-setup", { vault = vault, path = path }, {})
  if out and out.code == 0 then
    log.info "Vault configured successfully!"
  elseif out then
    log.err("Setup failed: %s", out.stderr)
  end
  return out
end

---@param path string?
function M.unlink(path)
  M.run("sync-unlink", { path = path or "" }, {
    callback = function(out)
      if out.code == 0 then
        log.info "Vault unlinked successfully!"
      else
        log.err("Unlink failed: %s", out.stderr)
      end
    end,
  })
end

---@class obsidian.sync.LocalVault
---@field id string
---@field host string

---@return table<string, obsidian.sync.LocalVault>
function M.list_local()
  local out = M.run_sync("sync-list-local", {}, { silent = true })
  if not out or out.code ~= 0 or not out.stdout then
    return {}
  end

  local lines = vim.split(out.stdout, "\n", { trimempty = true })
  local res = {}
  local current_id = nil
  local current_path = nil

  for _, line in ipairs(lines) do
    local id = line:match "^%s*([0-9a-fA-F]+)$"
    if id then
      current_id = id
      current_path = nil
    elseif current_id ~= nil and line:match "^%s+Path:%s+" then
      local vault_path = line:match "^%s+Path:%s+(.+)$"
      if vault_path then
        current_path = vault_path
        res[vault_path] = {
          id = current_id,
          host = "",
        }
      end
    elseif current_id ~= nil and current_path ~= nil and line:match "^%s+Host:%s+" then
      local host = line:match "^%s+Host:%s+(.+)$"
      if host then
        res[current_path].host = host
      end
    end
  end

  return res
end

---@param name string
---@param opts { encryption?: string, password?: string, region?: string }?
---@return { hash: string, name: string }|nil
function M.create_remote(name, opts)
  opts = opts or {}
  local args = { name = name }
  if opts.encryption then
    args.encryption = opts.encryption
  end
  if opts.password then
    args.password = opts.password
  end
  if opts.region then
    args.region = opts.region
  end

  local out = M.run_sync("sync-create-remote", args, {})
  if out and out.code == 0 and out.stdout then
    local vault_id = out.stdout:match "[Vv]ault ID:%s*([0-9a-fA-F]+)"
    return { hash = assert(vault_id, "failed to parse sync-create-remote result"), name = name }
  end
end

---@param path string?
---@param opts { conflict_strategy?: string, file_types?: string[], configs?: string[], excluded_folders?: string[], device_name?: string, config_dir?: string }?
function M.set_config(path, opts)
  opts = opts or {}
  local args = { path = path or "" }
  if opts.conflict_strategy then
    args["conflict-strategy"] = opts.conflict_strategy
  end
  if opts.file_types and #opts.file_types > 0 then
    args["file-types"] = table.concat(opts.file_types, ",")
  end
  if opts.configs and #opts.configs > 0 then
    args.configs = table.concat(opts.configs, ",")
  end
  if opts.excluded_folders and #opts.excluded_folders > 0 then
    args["excluded-folders"] = table.concat(opts.excluded_folders, ",")
  end
  if opts.device_name then
    args["device-name"] = opts.device_name
  end
  if opts.config_dir then
    args["config-dir"] = opts.config_dir
  end

  M.run("sync-config", args, {
    callback = function(out)
      if out.code == 0 then
        log.info "Config updated!"
      else
        log.err("Config update failed: %s", out.stderr)
      end
    end,
  })
end

---@param path string
---@param sync_opts obsidian.config.SyncOpts
function M.apply_config(path, sync_opts)
  local cfg = {}
  if sync_opts.conflict_strategy then
    cfg.conflict_strategy = sync_opts.conflict_strategy
  end
  if sync_opts.file_types and #sync_opts.file_types > 0 then
    cfg.file_types = sync_opts.file_types
  end
  if sync_opts.configs and #sync_opts.configs > 0 then
    cfg.configs = sync_opts.configs
  end
  if sync_opts.excluded_folders and #sync_opts.excluded_folders > 0 then
    cfg.excluded_folders = sync_opts.excluded_folders
  end
  if sync_opts.device_name then
    cfg.device_name = sync_opts.device_name
  end
  if sync_opts.config_dir then
    cfg.config_dir = sync_opts.config_dir
  end

  M.set_config(path, cfg)
end

return M
