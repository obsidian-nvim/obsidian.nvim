local api = require "obsidian.api"
local log = require "obsidian.log"
local status = require "obsidian.sync.status"

---@type table<string, vim.SystemObj>
local sync_proc = {}

---@type table<string, string[]>
local sync_log = {}

---@class obsidian.sync.Client
---@field cmd string?  -- path to CLI, if available
---@field cli obsidian.CLI?  -- CLI instance, if available
local M = {}

local function get_plugin_root()
  local root = vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
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
  if out.code == 2 then
    if api.confirm "Not logged in, login to your obsidian account?" == "Yes" then
      local success = M.login()
      if success then
        return M.cli:run_sync(subcmd, flags)
      end
    end
    return
  end
  return out
end

---@param subcmd string
---@param flags table<string, string|boolean>|?
---@param opts vim.SystemOpts|?
---@param callback fun(out: vim.SystemCompleted)
---@return vim.SystemObj|nil
function M.run_async(subcmd, flags, opts, callback)
  if not M.cli then
    log.err "CLI not initialized, cannot run command."
    return nil
  end
  opts = opts or {}

  return M.cli:run(
    subcmd,
    flags,
    opts,
    vim.schedule_wrap(function(out)
      if out.code == 2 then
        if api.confirm "Not logged in, login to your obsidian account?" == "Yes" then
          local success = M.login()
          if success then
            M.cli:run(subcmd, flags, opts, callback)
          end
        end
        return
      elseif out.code ~= 0 then
        local error_output = opts.cwd and sync_log[opts.cwd] and table.concat(sync_log[opts.cwd], "\n") or out.stderr
        if error_output:find "Another sync instance is already running for this vault." then
          log.info "Another sync instance is already running for this vault."
        else
          log.err("Command failed with code %s: %s", out.code, error_output)
        end
      else
        callback(out)
      end
    end)
  )
end

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
    log.info "Login successful!"
    return true
  else
    log.err("Login failed: %s", out and out.stderr)
    return false
  end
end

---@type table<string, obsidian.sync.LocalVault>|nil
local _local_vaults_cache = nil

M._local_vaults_cache = _local_vaults_cache

local function invalidate_cache()
  _local_vaults_cache = nil
end

M.invalidate_vaults_cache = invalidate_cache

---@param vault string  -- vault id or name
---@param path string
---@return vim.SystemCompleted|nil
function M.setup(vault, path)
  local out = M.run("sync-setup", { vault = vault, path = path })
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

---@return obsidian.sync.RemoteVault[]  -- list of remote vaults
function M.list_remote()
  local out = M.run "sync-list-remote"

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
    return { hash = assert(vault_id, "failed to parse sync-create-remote result"), name = name }
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

  return M.run("sync-config", args)
end

---@param path string?
---@return vim.SystemCompleted|nil
function M.logout()
  return M.run("logout", {})
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

--------------------------------
--- Sync Process Management ---
--------------------------------

---@param dir string
---@param message string
local function append_log(dir, message)
  if not message or message == "" then
    return
  end

  if not sync_log[dir] then
    sync_log[dir] = {}
  end

  local ts = os.date "%Y-%m-%d %H:%M"
  local lines = vim.split(message, "\n")

  for _, line in ipairs(lines) do
    if line and line ~= "" then
      if line == "Fully synced" then
        status.set(dir, "synced")
      elseif line:lower():find("paused", 1, true) then
        status.set(dir, "paused")
      else
        status.set(dir, "syncing")
      end
      local entry = string.format("%s - %s", ts, line)
      table.insert(sync_log[dir], entry)
    end
  end
end

---@param dir string
function M.pause(dir)
  if not sync_proc[dir] then
    return
  end

  local ok, err = pcall(function()
    sync_proc[dir]:kill(15)
    sync_proc[dir] = nil
    status.set(dir, "paused")
  end)
  return ok, err
end

---@param dir string
---@return fun(err, line)
local function make_handler(dir)
  return function(err, line)
    if err then
      log.err(err)
      append_log(dir, tostring(err))
    end
    if not line then
      return
    end
    line = vim.trim(line)
    if line == "" then
      return
    end
    append_log(dir, line)
  end
end

---@param dir string
function M.start(dir)
  local handler = make_handler(dir)

  if not M.cli then
    log.err "CLI not available, cannot start sync."
    return
  end

  if sync_proc[dir] ~= nil then
    log.info("Sync already running for %s", dir)
    return
  end

  local callback = function(out)
    if out.code ~= 0 then
      log.err("obsidian sync exited %s", out.stderr)
      append_log(dir, string.format("obsidian sync exited with code %s: %s", out.code, out.stderr))
    end
  end

  M.set_config(dir, Obsidian.opts.sync)

  sync_proc[dir] = M.run_async("sync", { continuous = true }, {
    cwd = dir,
    stderr = handler,
    stdout = handler,
  }, callback)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("obsidian-sync-" .. dir, { clear = true }),
    callback = function()
      M.pause(dir)
    end,
  })
end

---@param dir string
---@return { buf: integer }
function M.log(dir)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, sync_log[dir] or {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, ("Obsidian Sync Log %s"):format(dir))
  vim.api.nvim_set_current_buf(buf)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, silent = true })
  return { buf = buf }
end

return M
