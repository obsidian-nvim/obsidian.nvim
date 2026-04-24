local api = require "obsidian.api"
local log = require "obsidian.log"
local runner = require "obsidian.sync.runner"
local status = require "obsidian.sync.status"

local M = {
  name = "git",
  caps = { remote_catalog = false },
}

---@type table<string, uv.uv_timer_t>
local timers = {}

---@type table<string, boolean>
local in_flight = {}

---@return string
local function default_commit_message()
  local host = (vim.uv or vim.loop).os_gethostname() or "nvim"
  return string.format("obsidian: %s %s", host, os.date "%Y-%m-%d %H:%M:%S")
end

---@return string
local function commit_message()
  local fn = Obsidian.opts.sync.git and Obsidian.opts.sync.git.commit_message
  if type(fn) == "function" then
    local ok, msg = pcall(fn)
    if ok and type(msg) == "string" and msg ~= "" then
      return msg
    end
  end
  return default_commit_message()
end

---@return string
local function remote_name()
  local git_opts = Obsidian.opts.sync.git or {}
  return git_opts.remote or "origin"
end

---@param dir string
---@param args string[]
---@return vim.SystemCompleted
local function git(dir, args)
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { cwd = dir, text = true }):wait()
end

---@param dir string
---@return boolean
local function has_git_dir(dir)
  local out = git(dir, { "rev-parse", "--is-inside-work-tree" })
  return out.code == 0
end

---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws)
  local dir = tostring(ws.root)
  if not has_git_dir(dir) then
    return false
  end
  local out = git(dir, { "remote", "get-url", remote_name() })
  return out.code == 0
end

---@param dir string
---@param message string
local function logln(dir, message)
  runner.append_log(dir, message)
end

---@param dir string
---@param opts { silent: boolean? }?
---@return boolean ok
function M.sync_once(dir, opts)
  opts = opts or {}
  if in_flight[dir] then
    if not opts.silent then
      log.info("Sync already in progress for %s", dir)
    end
    return false
  end
  in_flight[dir] = true
  status.set "syncing"

  local remote = remote_name()
  local git_opts = Obsidian.opts.sync.git or {}

  local function fail(msg)
    in_flight[dir] = nil
    logln(dir, msg)
    status.set "paused"
    if not opts.silent then
      log.err(msg)
    end
  end

  logln(dir, "git: sync start")

  local add = git(dir, { "add", "-A" })
  if add.code ~= 0 then
    fail("git add failed: " .. (add.stderr or ""))
    return false
  end

  local diff = git(dir, { "diff", "--cached", "--quiet" })
  local has_changes = diff.code ~= 0

  if has_changes then
    local msg = commit_message()
    local commit = git(dir, { "commit", "-m", msg })
    if commit.code ~= 0 then
      fail("git commit failed: " .. (commit.stderr or ""))
      return false
    end
    logln(dir, "git commit: " .. msg)
  end

  local pull_args = { "pull", "--rebase", "--autostash", remote }
  if git_opts.branch then
    table.insert(pull_args, git_opts.branch)
  end
  local pull = git(dir, pull_args)
  if pull.code ~= 0 then
    fail("git pull --rebase failed: " .. (pull.stderr or ""))
    return false
  end

  local push_args = { "push", remote }
  if git_opts.branch then
    table.insert(push_args, git_opts.branch)
  end
  local push = git(dir, push_args)
  if push.code ~= 0 then
    fail("git push failed: " .. (push.stderr or ""))
    return false
  end

  logln(dir, "Fully synced")
  status.set "synced"
  in_flight[dir] = nil
  return true
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

  local interval = (Obsidian.opts.sync.git and Obsidian.opts.sync.git.poll_interval) or 30000

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
    group = vim.api.nvim_create_augroup("obsidian-sync-git-" .. dir, { clear = true }),
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
  local remote = remote_name()

  if not has_git_dir(dir) then
    if api.confirm("No git repo in " .. dir .. ". Initialize one?") ~= "Yes" then
      return
    end
    local init = git(dir, { "init" })
    if init.code ~= 0 then
      log.err("git init failed: %s", init.stderr)
      return
    end
  end

  local existing = git(dir, { "remote", "get-url", remote })
  if existing.code ~= 0 then
    local url = api.input(string.format("Remote URL for '%s'", remote))
    if not url or url == "" then
      log.info "Aborted"
      return
    end
    local add = git(dir, { "remote", "add", remote, url })
    if add.code ~= 0 then
      log.err("git remote add failed: %s", add.stderr)
      return
    end
  end

  log.info("Git sync configured for %s", dir)

  if api.confirm "Start syncing now?" == "Yes" then
    require("obsidian.sync").start(workspace)
  end
end

---@param workspace obsidian.Workspace
function M.disconnect(workspace)
  local dir = tostring(workspace.root)
  M.pause(dir)
  local remote = remote_name()
  if api.confirm(string.format("Remove git remote '%s'?", remote)) == "Yes" then
    git(dir, { "remote", "remove", remote })
  end
end

return M
