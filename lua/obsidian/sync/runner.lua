local log = require "obsidian.log"
local status = require "obsidian.sync.status"

---@class obsidian.sync.Runner
local M = {}

---@type table<string, vim.SystemObj>
M.procs = {}

---@type table<string, string[]>
M.logs = {}

-- Avoid notification spam when continuous sync keeps retrying with the same error.
local NOTIFY_INTERVAL_S = 60

---@type table<string, { msg: string, time: integer }>
local last_notified = {}

---@param dir string?
function M.clear_notify_state(dir)
  if dir then
    last_notified[dir] = nil
    return
  end

  for key in pairs(last_notified) do
    last_notified[key] = nil
  end
end

---@param line string
---@return string
local function notification_message(line)
  return vim.trim((line:gsub("^Error:%s*", "")))
end

---@param dir string
---@param line string
local function notify_error(dir, line)
  local msg = notification_message(line)
  local now = os.time()
  local prev = last_notified[dir]
  if prev and prev.msg == msg and now - prev.time < NOTIFY_INTERVAL_S then
    return
  end
  last_notified[dir] = { msg = msg, time = now }
  log.err("Sync error: %s", msg)
end

---@param line string
---@return boolean
local function is_error_line(line)
  return line:find "^Error:%s*" ~= nil or line:lower():find "^obsidian sync exited with code%s+%d+" ~= nil
end

---@param line string
---@return boolean
local function is_stack_trace(line)
  return line:find "^%s*at%s" ~= nil
end

---@param dir string
---@param message string
---@param opts { error?: boolean, notify?: boolean }?
function M.append_log(dir, message, opts)
  if not message or message == "" then
    return
  end

  opts = opts or {}

  if not M.logs[dir] then
    M.logs[dir] = {}
  end

  local ts = os.date "%Y-%m-%d %H:%M"
  local lines = vim.split(message, "\n")

  for _, line in ipairs(lines) do
    if line and line ~= "" then
      if line == "Fully synced" then
        status.set "synced"
      elseif line:lower():find("paused", 1, true) then
        status.set "paused"
      elseif opts.error or is_error_line(line) then
        status.set "error"
        if opts.notify ~= false then
          notify_error(dir, line)
        end
      elseif not is_stack_trace(line) and status.state.kind ~= "error" then
        -- stack-trace/progress lines after an error should not clear the error state.
        status.set "syncing"
      end
      local entry = string.format("%s - %s", ts, line)
      table.insert(M.logs[dir], entry)
    end
  end
end

---@param dir string
---@return fun(err: string?, line: string?)
function M.make_handler(dir)
  return function(err, line)
    if err then
      M.append_log(dir, tostring(err), { error = true })
    end
    if not line then
      return
    end
    line = vim.trim(line)
    if line == "" then
      return
    end
    M.append_log(dir, line)
  end
end

---@param dir string
---@return { buf: integer }
function M.open_log_buf(dir)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.logs[dir] or {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, ("Obsidian Sync Log %s"):format(dir))
  vim.api.nvim_set_current_buf(buf)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, silent = true })
  return { buf = buf }
end

return M
