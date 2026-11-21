local M = {}

---@param name string
---@return string?
local function plugin_path(name)
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.endswith(path, name) then
      return path
    end
  end
end

--- Find an installed plugin on runtimepath and report its Git revision, if available.
---@param name string
---@return { commit: string, path: string }?
function M.get_plugin_info(name)
  local path = plugin_path(name)
  if not path then
    return
  end
  local result = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = path }):wait(1000)
  return { path = path, commit = result.code == 0 and vim.trim(result.stdout or "") or "unknown" }
end

--- Get the bundled docs directory. This depends on finding the named plugin
--- directory on runtimepath and may not work with all package managers.
---@return obsidian.Path?
function M.docs_dir()
  local info = M.get_plugin_info "obsidian.nvim"
  if info then
    return require("obsidian.path").new(info.path) / "docs"
  end
end

return M
