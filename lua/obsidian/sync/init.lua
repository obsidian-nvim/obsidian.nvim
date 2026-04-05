local log = require "obsidian.log"
local client = require "obsidian.sync.client"
local status = require "obsidian.sync.status"

local M = {}

---@type table<string, vim.SystemObj>
local sync_proc = {}

---@type table<string, string[]>
local sync_log = {}

---@param workspace obsidian.Workspace
---@param message string
local function append_log(workspace, message)
  if not message or message == "" then
    return
  end

  local key = tostring(workspace.root)
  if not sync_log[key] then
    sync_log[key] = {}
  end

  local ts = os.date "%Y-%m-%d %H:%M"
  local lines = vim.split(message, "\n")

  for _, line in ipairs(lines) do
    if line and line ~= "" then
      if line == "Fully synced" then
        status.set(workspace, "synced")
      elseif line:lower():find("paused", 1, true) then
        status.set(workspace, "paused")
      else
        status.set(workspace, "syncing")
      end
      local entry = string.format("%s - %s", ts, line)
      table.insert(sync_log[key], entry)
    end
  end
end

---@param workspace obsidian.Workspace
local function stop_sync(workspace)
  local key = tostring(workspace.root)
  if not sync_proc[key] then
    return
  end

  pcall(function()
    sync_proc[key]:kill(15)
  end)

  sync_proc[key] = nil
  status.set(workspace, "paused")
end

---@param workspace obsidian.Workspace
---@return fun(err, line)
local function make_handler(workspace)
  return function(err, line)
    if err then
      log.err(err)
      append_log(workspace, tostring(err))
    end
    if not line then
      return
    end
    line = vim.trim(line)
    if line == "" then
      return
    end
    append_log(workspace, line)
  end
end

---@param workspace obsidian.Workspace
local function start_sync(workspace)
  local root = tostring(workspace.root)
  local handler = make_handler(workspace)

  if sync_proc[root] ~= nil then
    return
  end

  sync_proc[root] = vim.system({ client.get_cmd(), "sync", "--continuous" }, {
    cwd = tostring(workspace.root),
    stderr = handler,
    stdout = handler,
  }, function(out)
    if sync_proc[root] ~= nil then
      sync_proc[root] = nil
      status.set(workspace, "paused")
    end

    if out.code ~= 0 then
      log.err("obsidian sync exited", out)
      append_log(workspace, string.format("obsidian sync exited with code %s", tostring(out.code)))
    end
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("obsidian-sync-" .. root, { clear = true }),
    callback = function()
      stop_sync(workspace)
    end,
  })
end

---@param workspace? obsidian.Workspace
M.start = function(workspace)
  workspace = workspace or Obsidian.workspace
  start_sync(workspace)
end

---@param workspace? obsidian.Workspace
M.stop = function(workspace)
  workspace = workspace or Obsidian.workspace
  stop_sync(workspace)
end

local function open_log(workspace)
  workspace = workspace or Obsidian.workspace
  local key = tostring(workspace.root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, sync_log[key] or {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "Obsidian Sync Log")
  vim.api.nvim_set_current_buf(buf)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, silent = true })
end

local actions = {
  {
    name = "start",
    text = "Start Sync",
    fn = M.start,
  },
  {
    name = "pause",
    text = "Pause Sync",
    fn = M.stop,
  },
  {
    name = "log",
    text = "View Sync Log",
    fn = open_log,
  },
  {
    name = "wizard",
    text = "Setup Wizard",
    fn = function()
      require("obsidian.sync.wizard").wizard()
    end,
  },
}

M._actions = actions

---@param subcmd? string
M.menu = function(subcmd)
  if not subcmd then
    vim.ui.select(actions, {
      prompt = "Obsidian Sync",
      format_item = function(item)
        return item.text
      end,
    }, function(choice)
      if not choice then
        return
      end
      choice.fn()
    end)
    return
  end

  local action = vim.iter(actions):find(function(act)
    return act.name == subcmd
  end)
  if not action then
    return
  end
  action.fn()
end

M.is_configured = require("obsidian.sync.client").is_configured

return M
