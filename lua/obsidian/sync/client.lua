local api = require "obsidian.api"
local log = require "obsidian.log"

---@class obsidian.sync.Client
---@field cmd string?  -- path to CLI, if available
---@field cli obsidian.CLI?  -- CLI instance, if available
local M = {}

local function get_plugin_root()
  local root = require "obsidian.iter"(vim.api.nvim_list_runtime_paths()):find(function(path)
    return vim.endswith(path, "obsidian.nvim")
  end)
  return root
end

---@return string?
local function get_cmd()
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

---@return obsidian.CLI|nil
local function ensure_cli()
  local CLI = require "obsidian.cli"
  if M.cmd then
    return CLI.new(M.cmd)
  end
  if api.confirm "Obsidian CLI not found. Would you like to install it locally for obsidian.nvim?" == "Yes" then
    local success, new_cmd = install_local_cli()
    if success and new_cmd then
      return CLI.new(new_cmd)
    else
      log.err "CLI still not found after installation. Please report issue to repo."
    end
  end
end

local cmd, cli

---@param out vim.SystemCompleted|nil
---@return string
local function output_text(out)
  if not out then
    return ""
  end
  return table.concat({ out.stderr or "", out.stdout or "" }, "\n")
end

---@param out vim.SystemCompleted|nil
---@return boolean
local function is_not_logged_in(out)
  if not out or out.code ~= 2 then
    return false
  end

  local text = output_text(out):lower()
  return text:find("no account logged in", 1, true) ~= nil or text:find('run "ob login" first', 1, true) ~= nil
end

---@param out vim.SystemCompleted|nil
---@return boolean
local function is_password_validation_error(out)
  if not out or out.code ~= 2 then
    return false
  end

  return output_text(out):lower():find("failed to validate password", 1, true) ~= nil
end

setmetatable(M, {
  __index = function(_, k)
    if k == "cmd" then
      if not cmd then
        cmd = get_cmd()
      end
      return cmd
    elseif k == "cli" then
      if not cli then
        cli = ensure_cli()
      end
      return cli
    else
      return rawget(M, k)
    end
  end,
})

---@param subcmd string
---@param flags table<string, string|boolean>|?
function M.run(subcmd, flags)
  if not M.cli then
    log.err "CLI not initialized, cannot run command."
    return nil
  end

  local out = M.cli:run_sync(subcmd, flags)
  if is_not_logged_in(out) then
    if api.confirm "Not logged in, login to your obsidian account?" == "Yes" then
      local success = M.login()
      if success then
        return M.cli:run_sync(subcmd, flags)
      end
    end
    return
  elseif out.code ~= 0 then
    log.error(out.stderr)
  end
  return out
end

---@param lines string[]?
---@return boolean
local function has_error_lines(lines)
  for _, line in ipairs(lines or {}) do
    if line:find("Error:", 1, true) then
      return true
    end
  end
  return false
end

---@param subcmd string
---@param flags table<string, string|boolean>|?
---@param sys_opts vim.SystemOpts|?
---@param callback fun(out: vim.SystemCompleted)
---@param opts { silent: boolean? }?
---@return vim.SystemObj|nil
function M.run_async(subcmd, flags, sys_opts, callback, opts)
  if not M.cli then
    log.err "CLI not initialized, cannot run command."
    return nil
  end
  sys_opts = sys_opts or {}
  opts = opts or {}

  return M.cli:run(
    subcmd,
    flags,
    sys_opts,
    vim.schedule_wrap(function(out)
      if is_not_logged_in(out) then
        if api.confirm "Not logged in, login to your obsidian account?" == "Yes" then
          local success = M.login()
          if success then
            M.cli:run(subcmd, flags, sys_opts, callback)
          end
        end
        return
      elseif out.code ~= 0 then
        local runner = require "obsidian.sync.runner"
        local log_lines = sys_opts.cwd and runner.logs[sys_opts.cwd]
        local logged_error = has_error_lines(log_lines)
        local error_output = (log_lines and table.concat(log_lines, "\n")) or out.stderr or ""
        local already_running = error_output:find("Another sync instance is already running for this vault.", 1, true)
          ~= nil
        if sys_opts.cwd and not already_running then
          runner.append_log(
            sys_opts.cwd,
            string.format("obsidian sync exited with code %s: %s", out.code, out.stderr or ""),
            { error = true, notify = false }
          )
        end
        if already_running then
          if not opts.silent then
            log.info "Another sync instance is already running for this vault."
          end
        elseif not logged_error then
          log.err("Command failed with code %s: %s", out.code, error_output)
        end
      else
        callback(out)
      end
    end)
  )
end

---@type fun()|?
local invalidate_cache

---@param email string|?
---@param password string|?
---@return boolean
function M.login(email, password)
  email = email or api.input "Email"
  password = password or vim.fn.inputsecret "Password: "

  if not email or not password then
    log.err "Aborted"
    return false
  end

  local out = M.run("login", { email = email, password = password })

  if out ~= nil and out.code == 0 then
    local invalidate = invalidate_cache
    ---@cast invalidate -nil
    invalidate()
    log.info "Login successful!"
    return true
  else
    log.err("Login failed: %s", out and out.stderr)
    return false
  end
end

---@type table<string, obsidian.sync.LocalVault>|nil
local _local_vaults_cache = nil
---@type obsidian.sync.RemoteVault[]|nil
local _remote_vaults_cache = nil

M._local_vaults_cache = _local_vaults_cache
M._remote_vaults_cache = _remote_vaults_cache

invalidate_cache = function()
  _local_vaults_cache = nil
  _remote_vaults_cache = nil
  M._local_vaults_cache = nil
  M._remote_vaults_cache = nil
end

M.invalidate_vaults_cache = invalidate_cache

---@param vault string  -- vault id or name
---@param path string
---@param opts { password?: string, prompt_password?: boolean }?
---@return vim.SystemCompleted|nil
function M.setup(vault, path, opts)
  opts = opts or {}
  local args = { vault = vault, path = path }
  if opts.password and opts.password ~= "" then
    args.password = opts.password
  end

  local out = M.run("sync-setup", args)
  if is_password_validation_error(out) and opts.prompt_password ~= false and not args.password then
    local password = vim.fn.inputsecret "End-to-end encryption password: "
    if password and password ~= "" then
      args.password = password
      out = M.run("sync-setup", args)
    end
  end

  if out and out.code == 0 then
    invalidate_cache()
    log.info "Vault configured successfully!"
  elseif out then
    log.err("Setup failed: %s", out.stderr)
  end
  return out
end

---@class obsidian.sync.LocalVault
---@field hash string
---@field host string

---@param use_cache boolean? -- if true (default), return cached result when available
---@return table<string, obsidian.sync.LocalVault>
function M.list_local(use_cache)
  if use_cache ~= false and _local_vaults_cache then
    return _local_vaults_cache
  end

  local out = M.run("sync-list-local", {})
  if not out or out.code ~= 0 or not out.stdout then
    return {}
  end

  local lines = vim.split(out.stdout, "\n", { trimempty = true })
  local res = {}
  local current_hash = nil
  local current_path = nil

  for _, line in ipairs(lines) do
    local id = line:match "^%s*([0-9a-fA-F]+)$"
    if id then
      current_hash = id
      current_path = nil
    elseif current_hash ~= nil and line:match "^%s+Path:%s+" then
      local vault_path = line:match "^%s+Path:%s+(.+)$"
      if vault_path then
        current_path = vault_path
        res[vault_path] = {
          hash = current_hash,
          host = "",
        }
      end
    elseif current_hash ~= nil and current_path ~= nil and line:match "^%s+Host:%s+" then
      local host = line:match "^%s+Host:%s+(.+)$"
      if host then
        res[current_path].host = host
      end
    end
  end

  _local_vaults_cache = res
  M._local_vaults_cache = res
  return res
end

---@class obsidian.sync.RemoteVault
---@field hash string
---@field name string

---@param use_cache boolean? -- if true (default), return cached result when available
---@return obsidian.sync.RemoteVault[]  -- list of remote vaults
function M.list_remote(use_cache)
  if use_cache ~= false and _remote_vaults_cache then
    return _remote_vaults_cache
  end

  local out = M.run("sync-list-remote", {})

  if not out or out.code ~= 0 or not out.stdout then
    return {}
  end

  local lines = vim.split(out.stdout, "\n", { trimempty = true })
  local res = {}
  for _, line in ipairs(lines) do
    local hash, quoted_name = line:match '^%s*([0-9a-fA-F]+)%s+"([^"]+)"'
    local name
    if hash and quoted_name then
      name = quoted_name
    else
      hash, name = line:match "^%s*([0-9a-fA-F]+)%s+(.+)$"
      if name then
        name = vim.trim(name)
      end
    end

    if hash and name then
      table.insert(res, { hash = hash, name = name })
    end
  end

  _remote_vaults_cache = res
  M._remote_vaults_cache = res
  return res
end

---@param name string
---@param opts { encryption?: string, password?: string, region?: string }?
---@return obsidian.sync.RemoteVault|nil
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

  local out = M.run("sync-create-remote", args)
  if out and out.code == 0 and out.stdout then
    local vault_id = out.stdout:match "[Vv]ault ID:%s*([0-9a-fA-F]+)"
    if vault_id then
      _remote_vaults_cache = nil
      M._remote_vaults_cache = nil
      return { hash = vault_id, name = name }
    end
    log.err "Failed to parse sync-create-remote result."
  end
end

---@param path string?
---@param opts obsidian.config.SyncOpts?
---@return vim.SystemCompleted|nil
function M.set_config(path, opts)
  opts = opts or {}
  local args = { path = path or "" }
  if opts.mode then
    args.mode = opts.mode
  end
  if opts.conflict_strategy then
    args["conflict-strategy"] = opts.conflict_strategy
  end
  if opts.file_types and #opts.file_types > 0 then
    args["file-types"] = table.concat(opts.file_types, ",")
  end
  if opts.configs ~= nil then
    args.configs = #opts.configs > 0 and table.concat(opts.configs, ",") or ""
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

  return M.run("sync-config", args)
end

---@return vim.SystemCompleted|nil
function M.logout()
  local out = M.run("logout", {})
  if out and out.code == 0 then
    invalidate_cache()
  end
  return out
end

---@param path string?
---@return vim.SystemCompleted|nil
function M.unlink(path)
  local out = M.run("sync-unlink", { path = path or "" })
  if out and out.code == 0 then
    invalidate_cache()
  end
  return out
end

return M
