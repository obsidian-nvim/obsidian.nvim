---@class obsidian.CLI
local M = {}

M.__index = M

---@param cmd string
---@return obsidian.CLI
M.new = function(cmd)
  return setmetatable({ cmd = cmd }, M)
end

---@param cmd string
---@param subcmd string
---@param flags table<string, string|boolean>|?
---@return string[]
local function build_cmd(cmd, subcmd, flags)
  local cmds = { cmd, subcmd }
  for k, v in pairs(flags or {}) do
    table.insert(cmds, string.format("--%s", k))
    if type(v) ~= "boolean" and v ~= true then
      table.insert(cmds, v)
    end
  end
  return cmds
end

---@param subcmd string
---@param flags table<string, string|boolean>|?
---@param opts vim.SystemOpts|?
---@param callback fun(out: vim.SystemCompleted)
---@return vim.SystemObj
M.run = function(self, subcmd, flags, opts, callback)
  flags = flags or {}
  opts = opts or {}

  local cmds = build_cmd(self.cmd, subcmd, flags)
  return vim.system(cmds, opts, function(out)
    if callback then
      callback(out)
    end
  end)
end

---@param subcmd string
---@param flags table<string, string|boolean>|?
---@param opts vim.SystemOpts|?
---@return vim.SystemCompleted
M.run_sync = function(self, subcmd, flags, opts)
  flags = flags or {}
  opts = opts or {}

  local cmds = build_cmd(self.cmd, subcmd, flags)
  local out = vim.system(cmds, opts):wait()
  return out
end

return M
