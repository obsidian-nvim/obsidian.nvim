local api = require "obsidian.api"

local M = {}

--- Resolve the workspace when an integration source is invoked. This must not be
--- cached because the active workspace can change during a Neovim session.
---@return string
M.workspace_dir = function()
  return tostring(api.resolve_workspace_dir())
end

---@param ... table|?
---@return table
M.merge_opts = function(...)
  local count = select("#", ...)
  local opts = {}
  for i = 1, count do
    opts[i] = select(i, ...) or {}
  end
  local merged = vim.tbl_deep_extend("force", {}, unpack(opts, 1, count))
  ---@cast merged table
  return merged
end

---@param ... table|?
---@return table
M.workspace_opts = function(...)
  local opts = M.merge_opts(...)
  opts.cwd = M.workspace_dir()
  return opts
end

return M
