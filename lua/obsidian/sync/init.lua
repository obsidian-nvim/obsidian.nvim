local log = require "obsidian.log"

local M = {}

---@type table<string, vim.SystemObj>
local sync_proc = {}

---@type table<string, string[]>
local sync_log = {}

---@type table<string, string>
local sync_status = {}

local sync_icons = {
  synced = "󰸞",
  syncing = "󰑓",
  paused = "󰏤",
}

local group = {
  synced = "DiagnosticOk",
  syncing = "DiagnosticWarn",
  paused = "DiagnosticInfo",
}

vim.g.obsidian_sync_status_kind = "paused"
vim.g.obsidian_sync_status_icon = ""
vim.g.obsidian_sync_status = ""

function M.status_color()
  local workspace = Obsidian and Obsidian.workspace or nil
  local key = workspace and tostring(workspace.root) or nil
  local kind = key and sync_status[key] or nil

  local hl = group[kind]
  return hl or "DiagnosticInfo"
end

---@param kind? "synced" | "syncing" | "paused"
local function set_statusline_globals(kind)
  local icon = (kind and sync_icons[kind]) or ""
  local hl = group[kind] or "DiagnosticInfo"

  vim.g.obsidian_sync_status_kind = kind
  vim.g.obsidian_sync_status_icon = icon
  vim.g.obsidian_sync_status = icon ~= "" and string.format(" %%#%s# %s %%*", hl, icon) or ""
end

---@param workspace obsidian.Workspace
---@param kind "synced" | "syncing" | "paused"
local function set_status(workspace, kind)
  local key = tostring(workspace.root)
  sync_status[key] = kind

  local current = Obsidian and Obsidian.workspace or nil
  if not current or tostring(current.root) ~= key then
    return
  end

  set_statusline_globals(kind)
end

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
        set_status(workspace, "synced")
      elseif line:lower():find("paused", 1, true) then
        set_status(workspace, "paused")
      else
        set_status(workspace, "syncing")
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
  set_status(workspace, "paused")
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

  sync_proc[root] = vim.system({ "ob", "sync", "--continuous" }, {
    cwd = tostring(workspace.root),
    stderr = handler,
    stdout = handler,
  }, function(out)
    if sync_proc[root] ~= nil then
      sync_proc[root] = nil
      set_status(workspace, "paused")
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
  if workspace and not workspace.root then
    workspace = nil
  end

  workspace = workspace or Obsidian.workspace

  if not workspace then
    for path, proc in pairs(sync_proc) do
      pcall(function()
        proc:kill(15)
      end)

      sync_proc[path] = nil
      sync_status[path] = nil
    end
    set_statusline_globals(nil)
    return
  end

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

local function run_cmd(choice)
  if choice == "Start Sync" then
    M.start()
  elseif choice == "Pause Sync" then
    M.stop()
  elseif choice == "View Sync Log" then
    open_log()
  elseif choice == "Run Sync Setup Wizard" then
    require("obsidian.sync.wizard").wizard()
  end
end

---@param subcmd? string
M.menu = function(subcmd)
  if not subcmd then
    vim.ui.select({
      "Start Sync",
      "Pause Sync",
      "View Sync Log",
      "Run Sync Setup Wizard",
    }, {
      prompt = "Obsidian Sync",
    }, run_cmd)
    return
  end

  run_cmd(subcmd)
end

M.is_configured = require("obsidian.sync.client").is_configured

return M
