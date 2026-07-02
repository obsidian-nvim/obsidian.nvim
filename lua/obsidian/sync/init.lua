local log = require "obsidian.log"

local M = {}

---@class obsidian.sync.Backend
---@field name string
---@field caps table<string, boolean>
---@field is_configured fun(ws: obsidian.Workspace, cache: any?): boolean
---@field start fun(dir: string, opts?: { silent: boolean? })
---@field pause fun(dir: string)
---@field sync_once fun(dir: string, opts?: { silent: boolean? })
---@field setup fun(ws: obsidian.Workspace)
---@field disconnect fun(ws: obsidian.Workspace)
---@field log fun(dir: string)
---@field ws_formatter (fun(ws: obsidian.Workspace): string)?

---@class obsidian.sync.ActionOpts
---@field silent boolean?

---@type table<string, fun(): obsidian.sync.Backend>
local builtin_loaders = {
  obsidian = function()
    return require "obsidian.sync.backends.obsidian"
  end,
}

---@type table<string, obsidian.sync.Backend>
local registered = {}

---Register a custom sync backend.
---@param name string
---@param backend obsidian.sync.Backend
function M.register(name, backend)
  registered[name] = backend
end

---@return obsidian.sync.Backend?
function M.get_backend()
  local name = (Obsidian and Obsidian.opts and Obsidian.opts.sync and Obsidian.opts.sync.backend) or "obsidian"
  if registered[name] then
    return registered[name]
  end
  local loader = builtin_loaders[name]
  if loader then
    local ok, backend = pcall(loader)
    if ok and backend then
      registered[name] = backend
      return backend
    end
    log.err("Failed to load sync backend '%s'", name)
    return nil
  end
  log.err("Unknown sync backend '%s'", name)
  return nil
end

---@param workspace? obsidian.Workspace
---@param opts obsidian.sync.ActionOpts?
function M.start(workspace, opts)
  workspace = workspace or Obsidian.workspace
  opts = opts or {}
  local backend = M.get_backend()
  if not backend then
    return
  end
  backend.start(tostring(workspace.root), { silent = opts.silent })
end

---@param workspace? obsidian.Workspace
---@param opts obsidian.sync.ActionOpts?
function M.pause(workspace, opts)
  workspace = workspace or Obsidian.workspace
  opts = opts or {}
  local dir = tostring(workspace.root)
  local backend = M.get_backend()
  if not backend then
    return
  end
  local ok, err = backend.pause(dir)

  if opts.silent then
    return
  end

  if ok or ok == nil then
    log.info("Paused sync for %s", dir)
  else
    log.err("Failed to pause sync for %s: %s", dir, err)
  end
end

---@param workspace? obsidian.Workspace
function M.log(workspace)
  workspace = workspace or Obsidian.workspace
  local backend = M.get_backend()
  if not backend then
    return
  end
  backend.log(tostring(workspace.root))
end

---@param workspace? obsidian.Workspace
---@param opts obsidian.sync.ActionOpts?
function M.sync_once(workspace, opts)
  workspace = workspace or Obsidian.workspace
  opts = opts or {}
  local backend = M.get_backend()
  if not backend then
    return
  end
  if not backend.is_configured(workspace) then
    if not opts.silent then
      log.info("Sync not configured for %s", tostring(workspace.root))
    end
    return
  end
  backend.sync_once(tostring(workspace.root), { silent = opts.silent })
end

---@type table<string, uv.uv_timer_t>
local debounce_timers = {}

---Debounced one-shot sync. Coalesces rapid calls within the configured window.
---@param workspace? obsidian.Workspace
function M.sync_once_debounced(workspace)
  workspace = workspace or Obsidian.workspace
  local dir = tostring(workspace.root)
  local delay = vim.g.obsidian_sync_on_write_debounce_ms

  local prev = debounce_timers[dir]
  if prev then
    pcall(function()
      prev:stop()
      prev:close()
    end)
  end

  local t = assert(vim.uv.new_timer(), "failed to spawn timer")
  debounce_timers[dir] = t
  t:start(
    delay,
    0,
    vim.schedule_wrap(function()
      pcall(function()
        t:stop()
        t:close()
      end)
      debounce_timers[dir] = nil
      M.sync_once(workspace, { silent = true })
    end)
  )
end

---@param ws obsidian.Workspace
---@param cache any?
---@return boolean
function M.is_configured(ws, cache)
  local backend = M.get_backend()
  if not backend then
    return false
  end
  return backend.is_configured(ws, cache)
end

M.setup = function()
  require("obsidian.sync.manage").setup()
end

M.disconnect = function()
  require("obsidian.sync.manage").disconnect()
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
    fn = M.pause,
  },
  {
    name = "sync",
    text = "Sync Now (one-shot)",
    fn = function()
      M.sync_once()
    end,
  },
  {
    name = "log",
    text = "Open Sync Log",
    fn = M.log,
  },
  {
    name = "setup",
    text = "Setup Wizard",
    fn = M.setup,
  },
  {
    name = "disconnect",
    text = "Unlink Vault From Remote",
    fn = M.disconnect,
  },
}

M._actions = actions

---@param subcmd? string
function M.menu(subcmd)
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

  local action
  for _, act in ipairs(actions) do
    if act.name == subcmd then
      action = act
      break
    end
  end
  if not action then
    log.err("Unknown sync subcommand: " .. subcmd)
    return
  end
  action.fn()
end

return M
