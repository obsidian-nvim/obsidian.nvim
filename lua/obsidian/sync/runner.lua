local status = require "obsidian.sync.status"

---@class obsidian.sync.Runner
local M = {}

---@type table<string, vim.SystemObj>
M.procs = {}

---@type table<string, string[]>
M.logs = {}

---@param dir string
---@param message string
function M.append_log(dir, message)
  if not message or message == "" then
    return
  end

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
      else
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
  local log = require "obsidian.log"
  return function(err, line)
    if err then
      log.err(err)
      M.append_log(dir, tostring(err))
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
