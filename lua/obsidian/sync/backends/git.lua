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

---Generate conflict copy filename per Obsidian naming rules
---@param path string
---@param dir string
---@return string
local function conflict_name(path, dir)
  local stem, ext = path:match("^(.+)%.([^.]+)$")
  if not stem then
    stem = path
    ext = ""
  end
  local device_name = (Obsidian.opts.sync and Obsidian.opts.sync.device_name)
    or (vim.uv or vim.loop).os_gethostname()
    or "nvim"
  local timestamp = os.date("%Y%m%d%H%M")
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

---@param dir string
---@param args string[]
---@param callback? fun(out: vim.SystemCompleted) If provided, runs async
---@return vim.SystemCompleted? (sync mode only)
local function git(dir, args, callback)
  local cmd = { "git" }
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
local function has_git_dir(dir)
  local out = git(dir, { "rev-parse", "--is-inside-work-tree" })
  return out.code == 0
end

---Resolve merge conflicts by creating conflict copies per Obsidian rules
---@param dir string
---@param remote_branch string
---@param callback fun(success: boolean)
local function resolve_conflicts(dir, remote_branch, callback)
  local uv = vim.uv or vim.loop
  git(dir, { "ls-files", "-u" }, function(ls_out)
    if ls_out.code ~= 0 then
      log.err("Failed to list unmerged files: " .. (ls_out.stderr or ""))
      callback(false)
      return
    end

    local files = {}
    for line in ls_out.stdout:gmatch("[^\r\n]+") do
      local stage, path = line:match("^%d+ %x+ (%d+) (.+)$")
      if stage == "2" or stage == "3" then
        files[path] = true
      end
    end

    local conflict_paths = {}
    for path in pairs(files) do
      table.insert(conflict_paths, path)
    end

    if #conflict_paths == 0 then
      callback(true)
      return
    end

    local pending = #conflict_paths
    local failed = false

    for _, path in ipairs(conflict_paths) do
      if failed then break end

      -- Read ours (stage 2)
      git(dir, { "show", ":2:" .. path }, function(ours_out)
        if failed then return end
        if ours_out.code ~= 0 then
          log.err("Failed to read ours for " .. path .. ": " .. (ours_out.stderr or ""))
          failed = true
          callback(false)
          return
        end

        -- Read theirs (stage 3)
        git(dir, { "show", ":3:" .. path }, function(theirs_out)
          if failed then return end
          if theirs_out.code ~= 0 then
            log.err("Failed to read theirs for " .. path .. ": " .. (theirs_out.stderr or ""))
            failed = true
            callback(false)
            return
          end

          -- Write theirs to original path
          local theirs_content = theirs_out.stdout
          uv.fs_write(dir .. "/" .. path, theirs_content, 0, function(write_err)
            if failed then return end
            if write_err then
              log.err("Failed to write theirs content to " .. path .. ": " .. write_err)
              failed = true
              callback(false)
              return
            end

            -- Write ours to conflict copy
            local conflict_path = conflict_name(path, dir)
            local ours_content = ours_out.stdout
            uv.fs_write(dir .. "/" .. conflict_path, ours_content, 0, function(write_ours_err)
              if failed then return end
              if write_ours_err then
                log.err("Failed to write conflict copy " .. conflict_path .. ": " .. write_ours_err)
                failed = true
                callback(false)
                return
              end

              -- Stage both files
              git(dir, { "add", path, conflict_path }, function(add_out)
                if failed then return end
                pending = pending - 1
                if pending == 0 and not failed then
                  callback(true)
                end
              end)
            end)
          end)
        end)
      end)
    end
  end)
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

  local remote = remote_name()
  local git_opts = Obsidian.opts.sync.git or {}
  local sync_opts = Obsidian.opts.sync

  local function fail(msg)
    in_flight[dir] = nil
    runner.append_log(dir, msg)
    status.set "paused"
    if not opts.silent then
      log.err(msg)
    end
  end

  runner.append_log(dir, "git: sync start")

  -- Step 1: Stage all changes (sync, fast local op)
  local add = git(dir, { "add", "-A" })
  if add.code ~= 0 then
    fail("git add failed: " .. (add.stderr or ""))
    return
  end

  -- Step 2: Check for staged changes (sync)
  local diff = git(dir, { "diff", "--cached", "--quiet" })
  local has_changes = diff.code ~= 0

  -- Helper to push changes (async)
  local function do_push(callback)
    local push_args = { "push", remote }
    local branch = git_opts.branch
    if not branch then
      local branch_out = git(dir, { "rev-parse", "--abbrev-ref", "HEAD" })
      if branch_out.code ~= 0 then
        fail("Failed to get current branch: " .. (branch_out.stderr or ""))
        callback(false)
        return
      end
      branch = branch_out.stdout:gsub("\n", "")
    end
    table.insert(push_args, branch)

    git(dir, push_args, function(push_out)
      if push_out.code ~= 0 then
        fail("git push failed: " .. (push_out.stderr or ""))
        callback(false)
        return
      end
      runner.append_log(dir, "Fully synced")
      status.set "synced"
      in_flight[dir] = nil
      callback(true)
    end)
  end

  -- After commit, handle pull/push based on conflict strategy
  local function after_commit()
    local conflict_strategy = (sync_opts and sync_opts.conflict_strategy) or "merge"

    if conflict_strategy == "conflict" then
      -- Conflict strategy: fetch, merge, handle conflicts
      git(dir, { "fetch", remote }, function(fetch_out)
        if fetch_out.code ~= 0 then
          fail("git fetch failed: " .. (fetch_out.stderr or ""))
          return
        end

        -- Get local head
        local local_head_out = git(dir, { "rev-parse", "HEAD" })
        if local_head_out.code ~= 0 then
          fail("Failed to get local HEAD: " .. (local_head_out.stderr or ""))
          return
        end
        local local_head = local_head_out.stdout:gsub("\n", "")

        -- Get current branch
        local branch_out = git(dir, { "rev-parse", "--abbrev-ref", "HEAD" })
        if branch_out.code ~= 0 then
          fail("Failed to get current branch: " .. (branch_out.stderr or ""))
          return
        end
        local current_branch = branch_out.stdout:gsub("\n", "")
        local remote_branch = remote .. "/" .. (git_opts.branch or current_branch)

        -- Get remote head
        local remote_head_out = git(dir, { "rev-parse", remote_branch })
        if remote_head_out.code ~= 0 then
          fail("Failed to get remote head: " .. (remote_head_out.stderr or ""))
          return
        end
        local remote_head = remote_head_out.stdout:gsub("\n", "")

        -- Get merge base
        local base_out = git(dir, { "merge-base", "HEAD", remote_branch })
        if base_out.code ~= 0 then
          fail("Failed to get merge base: " .. (base_out.stderr or ""))
          return
        end
        local base = base_out.stdout:gsub("\n", "")

        -- Handle merge cases
        if local_head == remote_head then
          do_push(function() end)
        elseif base == local_head then
          -- We are behind, fast-forward merge
          git(dir, { "merge", "--ff-only", remote_branch }, function(merge_out)
            if merge_out.code ~= 0 then
              fail("git merge --ff-only failed: " .. (merge_out.stderr or ""))
              return
            end
            do_push(function() end)
          end)
        elseif base == remote_head then
          -- Remote is behind, push
          do_push(function() end)
        else
          -- Diverged, attempt merge
          git(dir, { "merge", "--no-ff", "--no-commit", remote_branch }, function(merge_out)
            if merge_out.code == 0 then
              -- Merge succeeded, commit
              git(dir, { "commit", "-m", "sync: merge " .. remote_branch }, function(commit_out)
                if commit_out.code ~= 0 then
                  fail("Failed to commit merge: " .. (commit_out.stderr or ""))
                  return
                end
                do_push(function() end)
              end)
            else
              -- Conflict, resolve
              resolve_conflicts(dir, remote_branch, function(success)
                if not success then
                  fail("Failed to resolve conflicts")
                  return
                end
                git(dir, { "commit", "-m", "sync: merge " .. remote_branch .. " with conflict copies" }, function(commit_out)
                  if commit_out.code ~= 0 then
                    fail("Failed to commit conflict resolution: " .. (commit_out.stderr or ""))
                    return
                  end
                  do_push(function() end)
                end)
              end)
            end
          end)
        end
      end)
    else
      -- Default merge strategy: pull --rebase (async)
      local pull_args = { "pull", "--rebase", "--autostash", remote }
      local branch = git_opts.branch
      if not branch then
        local branch_out = git(dir, { "rev-parse", "--abbrev-ref", "HEAD" })
        if branch_out.code ~= 0 then
          fail("Failed to get current branch: " .. (branch_out.stderr or ""))
          return
        end
        branch = branch_out.stdout:gsub("\n", "")
      end
      table.insert(pull_args, branch)

      git(dir, pull_args, function(pull_out)
        if pull_out.code ~= 0 then
          fail("git pull --rebase failed: " .. (pull_out.stderr or ""))
          return
        end
        do_push(function() end)
      end)
    end
  end

  -- Commit if there are changes, then proceed
  if has_changes then
    local msg = commit_message()
    local commit = git(dir, { "commit", "-m", msg })
    if commit.code ~= 0 then
      fail("git commit failed: " .. (commit.stderr or ""))
      return
    end
    runner.append_log(dir, "git commit: " .. msg)
  end

  after_commit()
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
