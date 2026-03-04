local cli = require "obsidian.cli"
local api = require "obsidian.api"
local log = require "obsidian.log"

-- TODO: statusline indicator in footer
-- TODO: logs, settings?
-- TODO: choose watch mode or autocmd sync, or LSP didChange sync

---@class obsidian.Headless
---@field cli obsidian.CLI
local M = {}

M.__index = M

local function get_plugin_root()
  local root = vim.iter(vim.api.nvim_list_runtime_paths()):find(function(path)
    return vim.endswith(path, "obsidian.nvim")
  end)
  return root
end

---@return string?
function M.detect_cmd()
  local plugin_root = get_plugin_root()
  local cmd
  if plugin_root then
    local local_bin = vim.fs.joinpath(plugin_root, "node_modules", ".bin", "obsidian-headless")
    if vim.fn.executable(local_bin) == 1 then
      cmd = local_bin
    end
  end

  if not cmd and vim.fn.executable "ob" == 1 then
    cmd = "ob"
  end

  if not cmd then
    log.err "obsidian-headless not found. Run 'npm install obsidian-headless' in plugin folder."
  end
  return cmd
end

function M.new()
  local cmd = M.detect_cmd()
  if not cmd then
    return nil
  end
  return setmetatable({
    cli = cli.new(cmd, {}),
  }, M)
end

function M.run_sync(self, cmd, flags, opts)
  local out = self.cli:run_sync(cmd, flags, opts)
  if out.code == 2 then
    -- TODO: prompt to confirm login?
    if api.confirm "Not login in, confirm to enter your obsidian account" == "Yes" then
      self:login_sync()
      return self.cli.run_sync(cmd, flags, opts)
    end
    return
  end
  return out
end

function M.check_installed()
  local cmd = M.detect_cmd()
  return cmd ~= nil
end

---@param email string
---@param password string
function M.login(self, email, password)
  email = email or api.input "Email"
  password = password or vim.fn.inputsecret "Password: "

  if not email or not password then
    log.err "Email and password are required for login."
    return
  end

  self.cli:run("login", {
    email = email,
    password = password,
  }, {
    callback = function(out)
      if out.code == 0 then
        log.info "Login successful!"
      else
        log.err("Login failed: %s", out.stderr)
      end
    end,
  })
end

---@param email string
---@param password string
function M.login_sync(self, email, password)
  email = email or api.input "Email"
  password = password or vim.fn.inputsecret "Password: "

  if not email or not password then
    log.err "Email and password are required for login."
    return
  end

  local out = self:run_sync("login", { email = email, password = password }, {})

  if out.code == 0 then
    log.info "Login successful!"
  else
    log.err("Login failed: %s", out.stderr)
  end
  return out
end

function M.logout(self)
  self.cli:run("logout", {}, {
    callback = function(out)
      if out.code == 0 then
        log.info "Logout successful!"
      else
        log.err("Logout failed: %s", out.stderr)
      end
    end,
  })
end

---@return { hash: string, name: string }[]?  -- list of remote vaults
function M.list_remote(self)
  local out = self:run_sync("sync-list-remote", {}, { silent = true })

  if not out then
    return nil
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

  if vim.tbl_isempty(res) then
    log.info "No remote vaults found."
    return nil
  end
  return res
end

---@param path string
---@return boolean
function M.is_configured(self, path)
  local vaults = self:list_local()
  if not vaults then
    return false
  end
  return vaults[path] ~= nil
end

---@param vault string  -- vault id or name
---@param path string
function M.setup(self, vault, path)
  self.cli:run("sync-setup", {
    vault = vault,
    path = path,
  }, {
    callback = function(out)
      if out.code == 0 then
        log.info "Vault configured successfully!"
      else
        log.err("Setup failed: %s", out.stderr)
      end
    end,
  })
end

---@param path string
---@param watch boolean
function M.sync(self, path, watch)
  -- TODO:
  -- if watch then
  --   table.insert(args, "--continuous")
  -- end

  self.cli:run("sync", { path = path }, {
    callback = function(out)
      if out.code == 0 then
        log.info "Sync completed!"
      else
        log.err("Sync failed: %s", out.stderr)
      end
    end,
  })
end

---@param path string?
---@return string?
function M.status(self, path)
  local out = self:run_sync("sync-status", { path = path or "" }, { silent = true })
  if not out or out.code ~= 0 then
    return nil
  end
  return out.stdout
end

---@param path string?
function M.unlink(self, path)
  self.cli:run("sync-unlink", { path = path or "" }, {
    callback = function(out)
      if out.code == 0 then
        log.info "Vault unlinked successfully!"
      else
        log.err("Unlink failed: %s", out.stderr)
      end
    end,
  })
end

---@class obsidian.SyncVault
---@field id string
---@field path string
---@field host string

---@return table<string, obsidian.SyncVault>?  -- keyed by path
function M.list_local(self)
  local out = self:run_sync("sync-list-local", {}, { silent = true })
  if not out or out.code ~= 0 then
    return nil
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
        res[vault_path] = { id = current_id, path = vault_path, host = "" }
      end
    elseif current_id ~= nil and current_path ~= nil and line:match "^%s+Host:%s+" then
      local host = line:match "^%s+Host:%s+(.+)$"
      if host then
        res[current_path].host = host
      end
    end
  end

  if vim.tbl_isempty(res) then
    return nil
  end
  return res
end

---@param name string
---@param opts { encryption?: string, password?: string, region?: string }?
function M.create_remote(self, name, opts)
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

  self.cli:run("sync-create-remote", args, {
    callback = function(out)
      if out.code == 0 then
        log.info "Remote vault created!"
      else
        log.err("Create failed: %s", out.stderr)
      end
    end,
  })
end

---@param path string?
---@return string?
function M.get_config(self, path)
  local out = self:run_sync("sync-config", { path = path or "" }, { silent = true })
  if not out or out.code ~= 0 then
    return nil
  end
  return out.stdout
end

---@param path string?
---@param opts { conflict_strategy?: string, file_types?: string[], configs?: string[], excluded_folders?: string[], device_name?: string, config_dir?: string }?
function M.set_config(self, path, opts)
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

  self.cli:run("sync-config", args, {
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
function M.apply_config(self, path, sync_opts)
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

  self:set_config(path, cfg)
end

local m = M.new()
-- m:logout()
-- m:login()
vim.print(m:list_remote())

return M
