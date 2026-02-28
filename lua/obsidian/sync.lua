local cli = require "obsidian.cli"
local api = require "obsidian.api"

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
    vim.notify(
      "obsidian-headless not found. Run 'npm install obsidian-headless' in plugin folder.",
      vim.log.levels.ERROR
    )
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

function M.check_installed()
  local cmd = M.detect_cmd()
  return cmd ~= nil
end

---@param email string?
---@param password string?
function M.login(self, email, password)
  email = email or api.input "Email: "
  password = password or api.input "Password: "

  if not email or not password then
    vim.notify("Email and password are required for login.", vim.log.levels.ERROR)
    return
  end

  self.cli:run("login", {
    email = email,
    password = password,
  }, {
    callback = function(out)
      if out.code == 0 then
        vim.notify("Login successful!", vim.log.levels.INFO)
      else
        vim.notify("Login failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

---@return string[]?
function M.list_remote(self)
  local out = self.cli:run_sync("sync-list-remote", {}, { silent = true })

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
    vim.notify("No remote vaults found.", vim.log.levels.INFO)
    return nil
  end
  return res
end

---@param path string
---@return boolean
function M.is_configured(self, path)
  local out = self.cli:run_sync("sync-status", { path = path }, { silent = true })
  return out and out.code == 0 and out.stdout and out.stdout:match "%S"
end

---@param vault_name string
---@param path string
function M.setup(self, vault_name, path)
  self.cli:run("sync-setup", {
    vault = vault_name,
    path = path,
  }, {
    callback = function(out)
      if out.code == 0 then
        vim.notify("Vault configured successfully!", vim.log.levels.INFO)
      else
        vim.notify("Setup failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

---@param path string
---@param watch boolean
function M.sync(self, path, watch)
  local args = { "sync", path = path }
  if watch then
    table.insert(args, "--continuous")
  end

  self.cli:run("sync", args, {
    callback = function(out)
      if out.code == 0 then
        vim.notify("Sync completed!", vim.log.levels.INFO)
      else
        vim.notify("Sync failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

---@param path string?
---@return string?
function M.status(self, path)
  local out = self.cli:run_sync("sync-status", { path = path or "" }, { silent = true })
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
        vim.notify("Vault unlinked successfully!", vim.log.levels.INFO)
      else
        vim.notify("Unlink failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

---@return string[]?
function M.list_local(self)
  local out = self.cli:run_sync("sync-list-local", {}, { silent = true })
  if not out or out.code ~= 0 then
    return nil
  end

  local lines = vim.split(out.stdout, "\n", { trimempty = true })
  local res = {}
  for _, line in ipairs(lines) do
    if line:match "%S" then
      table.insert(res, line)
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
        vim.notify("Remote vault created!", vim.log.levels.INFO)
      else
        vim.notify("Create failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

---@param path string?
---@return string?
function M.get_config(self, path)
  local out = self.cli:run_sync("sync-config", { path = path or "" }, { silent = true })
  if not out or out.code ~= 0 then
    return nil
  end
  return out.stdout
end

---@param path string?
---@param opts { conflict_strategy?: string, file_types?: string, configs?: string, excluded_folders?: string, device_name?: string, config_dir?: string }?
function M.set_config(self, path, opts)
  opts = opts or {}
  local args = { path = path or "" }
  if opts.conflict_strategy then
    args["conflict-strategy"] = opts.conflict_strategy
  end
  if opts.file_types then
    args["file-types"] = opts.file_types
  end
  if opts.configs then
    args.configs = opts.configs
  end
  if opts.excluded_folders then
    args["excluded-folders"] = opts.excluded_folders
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
        vim.notify("Config updated!", vim.log.levels.INFO)
      else
        vim.notify("Config update failed: " .. out.stderr, vim.log.levels.ERROR)
      end
    end,
  })
end

return M
