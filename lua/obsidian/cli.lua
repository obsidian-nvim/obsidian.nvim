---@class obsidian.CLI
local M = {}

-- TODO: a live interface with completions like vim-fuigitive

M.__index = M

---@class obsidian.CLIOpts
---@field callback? fun(out: vim.SystemCompleted)
---@field silent? boolean

---@param cmd string
---@param opts obsidian.CLIOpts
---@return obsidian.CLI
M.new = function(cmd, opts)
  return setmetatable({
    cmd = cmd,
    opts = opts or {},
  }, M)
end

local function build_cmd(cmd, subcmd, flags)
  local cmds = { cmd, subcmd }
  for k, v in pairs(flags) do
    table.insert(cmds, string.format("--%s", k))
    if type(v) ~= "boolean" and v ~= true then
      table.insert(cmds, v)
    end
  end
  return cmds
end

---@param subcmd string
---@param flags table<string, string>|?
---@param opts obsidian.CLIOpts|?
---@return vim.SystemObj
M.run = function(self, subcmd, flags, opts)
  flags = flags or {}
  opts = opts or {}

  local cmds = build_cmd(self.cmd, subcmd, flags)
  local callback = self.opts.callback or opts.callback
  local silent = self.opts.silent or opts.silent -- TODO: this is a bit hacky, maybe we should merge opts in the constructor instead?

  return vim.system(cmds, {}, function(out)
    if not silent and out.code ~= 0 then
      vim.notify(string.format("Command failed: %s", table.concat(cmds, " ")), vim.log.levels.ERROR)
      return
    end

    if callback then
      callback(out)
    end
  end)
end

M.run_sync = function(self, subcmd, flags, opts)
  flags = flags or {}
  opts = opts or {}

  local cmds = build_cmd(self.cmd, subcmd, flags)
  local out = vim.system(cmds, {}, nil):wait()
  if not opts.silent and out.code ~= 0 then -- BUG:
    vim.notify(string.format("Command failed: %s", table.concat(cmds, " ")), vim.log.levels.ERROR)
    return out
  end

  return out
end

return M
