local log = require "obsidian.log"
local runner = require "obsidian.sync.runner"
local status = require "obsidian.sync.status"

local M = {
  name = "rclone",
  caps = { remote_catalog = false },
}

---@type table<string, uv.uv_timer_t>
local timers = {}

---@type table<string, boolean>
local in_flight = {}

---@return string
local function default_remote()
  local rclone_opts = Obsidian.opts.sync and Obsidian.opts.sync.rclone or {}
  return rclone_opts.remote or "remote"
end

---@return string
local function default_path()
  local rclone_opts = Obsidian.opts.sync and Obsidian.opts.sync.rclone or {}
  return rclone_opts.path or ""
end

---@param dir string
---@param args string[]
---@param callback? fun(out: vim.SystemCompleted) If provided, runs async
---@return vim.SystemCompleted? (sync mode only)
local function rclone(dir, args, callback)
  local cmd = { "rclone" }
  vim.list_extend(cmd, args)
  if callback then
    vim.system(cmd, { cwd = dir, text = true }, function(out)
      vim.schedule(function()
        callback(out)
      end)
    end)
  else
    return vim.system(cmd, { cwd = dir, text = true }):wait()
  end
end

---@param dir string
---@return boolean
local function has_rclone(dir)
  local out = rclone(dir, { "--version" })
  return out and out.code == 0 or false
end

---@param dir string
---@return boolean
local function is_remote_configured(dir)
  local remote = default_remote()
  local out = rclone(dir, { "config", "show" })
  if not out or out.code ~= 0 then
    return false
  end
  -- Check if remote exists in config
  return out.stdout:match("%[" .. remote .. "%]") ~= nil
end

---@param dir string
---@return string
local function get_remote_path(dir)
  local remote = default_remote()
  local path = default_path()
  if path == "" then
    -- Use vault name as default path
    local ws = Obsidian.workspace
    path = ws and ws.name or "vault"
  end
  return string.format("%s:%s", remote, path)
end

---Generate conflict copy filename per Obsidian naming rules
---@param path string
---@param dir string
---@return string
local function conflict_name(path, dir)
  local stem, ext = path:match "^(.+)%.([^.]+)$"
  if not stem then
    stem = path
    ext = ""
  end
  local device_name = (Obsidian.opts.sync and Obsidian.opts.sync.device_name)
    or (vim.uv or vim.loop).os_gethostname()
    or "nvim"
  local timestamp = os.date "%Y%m%d%H%M"
  local base_name
  if ext ~= "" then
    base_name = string.format("%s (Conflicted copy %s %s).%s", stem, device_name, timestamp, ext)
  else
    base_name = string.format("%s (Conflicted copy %s %s)", stem, device_name, timestamp)
  end

  -- Handle naming collisions
  local candidate = base_name
  local counter = 2
  local uv = vim.uv or vim.loop
  while uv.fs_stat(dir .. "/" .. candidate) do
    if ext ~= "" then
      candidate = string.format("%s (Conflicted copy %s %s)-%d.%s", stem, device_name, timestamp, counter, ext)
    else
      candidate = string.format("%s (Conflicted copy %s %s)-%d", stem, device_name, timestamp, counter)
    end
    counter = counter + 1
  end
  return candidate
end

---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws)
  local dir = tostring(ws.root)
  if not has_rclone(dir) then
    return false
  end
  return is_remote_configured(dir)
end

---@param dir string
---@param opts { silent: boolean? }?
function M.sync_once(dir, opts)
  opts = opts or {}
  if in_flight[dir] then
    if not opts.silent then
      log.info("Sync already in progress for %s", dir)
    end
    return
  end
  in_flight[dir] = true
  status.set "syncing"

  local sync_opts = Obsidian.opts.sync or {}
  local rclone_opts = sync_opts.rclone or {}
  local mode = sync_opts.mode or "mirror-remote"
  local conflict_strategy = sync_opts.conflict_strategy or "merge"

  local remote_path = get_remote_path(dir)

  local function fail(msg)
    in_flight[dir] = nil
    runner.append_log(dir, msg)
    status.set "paused"
    if not opts.silent then
      log.err(msg)
    end
  end

  runner.append_log(dir, "rclone: sync start (mode: " .. mode .. ")")

  if mode == "pull-only" then
    -- Pull from remote to local
    local args = { "sync", remote_path, dir, "--progress" }
    if conflict_strategy == "conflict" then
      vim.list_extend(args, { "--conflict-resolve", "largest" })
    end
    rclone(dir, args, function(out)
      in_flight[dir] = nil
      if out.code ~= 0 then
        fail("rclone sync failed: " .. (out.stderr or out.stdout or ""))
        return
      end
      runner.append_log(dir, "Pull sync completed")
      status.set "synced"
    end)
  elseif mode == "bidirectional" then
    -- Bidirectional: sync both ways (remote first, then local)
    local pull_args = { "sync", remote_path, dir, "--progress" }
    rclone(dir, pull_args, function(pull_out)
      if pull_out.code ~= 0 then
        fail("rclone pull failed: " .. (pull_out.stderr or pull_out.stdout or ""))
        return
      end

      local push_args = { "sync", dir, remote_path, "--progress" }
      rclone(dir, push_args, function(push_out)
        in_flight[dir] = nil
        if push_out.code ~= 0 then
          fail("rclone push failed: " .. (push_out.stderr or push_out.stdout or ""))
          return
        end
        runner.append_log(dir, "Bidirectional sync completed")
        status.set "synced"
      end)
    end)
  else
    -- mirror-remote (default): push local to remote
    local args = { "sync", dir, remote_path, "--progress" }
    if conflict_strategy == "conflict" then
      vim.list_extend(args, { "--conflict-resolve", "largest" })
    end
    rclone(dir, args, function(out)
      in_flight[dir] = nil
      if out.code ~= 0 then
        fail("rclone sync failed: " .. (out.stderr or out.stdout or ""))
        return
      end
      runner.append_log(dir, "Mirror sync completed")
      status.set "synced"
    end)
  end
end

---@param dir string
---@param opts { silent: boolean? }?
function M.start(dir, opts)
  opts = opts or {}
  if timers[dir] then
    if not opts.silent then
      log.info("Sync already running for %s", dir)
    end
    return
  end

  local interval = (Obsidian.opts.sync and Obsidian.opts.sync.write_debounce_ms) or 30000

  vim.schedule(function()
    M.sync_once(dir, { silent = opts.silent })
  end)

  local t = (vim.uv or vim.loop).new_timer()
  timers[dir] = t
  t:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      M.sync_once(dir, { silent = true })
    end)
  )

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("obsidian-sync-rclone-" .. dir, { clear = true }),
    callback = function()
      M.pause(dir)
    end,
  })
end

---@param dir string
function M.pause(dir)
  local t = timers[dir]
  if t then
    pcall(function()
      t:stop()
      t:close()
    end)
    timers[dir] = nil
  end
  status.set "paused"
  return true
end

---@param dir string
function M.log(dir)
  runner.open_log_buf(dir)
end

---@param workspace obsidian.Workspace
function M.setup(workspace)
  local dir = tostring(workspace.root)
  local remote = default_remote()

  if not has_rclone(dir) then
    log.err "rclone not found. Please install rclone first: https://rclone.org/install/"
    return
  end

  if not is_remote_configured(dir) then
    log.info "rclone remote not configured. Please run 'rclone config' in your terminal to set up a remote."
    log.info "After configuring, set the remote name in your obsidian.nvim config:"
    log.info("sync = { rclone = { remote = '" .. remote .. "' } }")
    return
  end

  log.info("rclone sync configured for %s with remote '%s'", dir, remote)

  if vim.fn.confirm("Start syncing now?", "&Yes\n&No", 2) == 1 then
    require("obsidian.sync").start(workspace)
  end
end

---@param workspace obsidian.Workspace
function M.disconnect(workspace)
  local dir = tostring(workspace.root)
  M.pause(dir)
  log.info("rclone sync disconnected. To remove the remote, run: rclone config delete " .. default_remote())
end

return M
