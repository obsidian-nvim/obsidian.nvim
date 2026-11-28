local M = {}

--- Get the path to where a plugin is installed.
---
---@param name string
---@return string|?
local get_src_root = function(name)
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if vim.endswith(path, name) then
      return path
    end
  end
end

--- Get info about a plugin.
---
---@param name string
---
---@return { commit: string|?, path: string }|?
M.get_plugin_info = function(name)
  local src_root = get_src_root(name)
  if not src_root then
    return
  end
  local out = { path = src_root }
  local obj = vim.system({ "git", "rev-parse", "HEAD" }, { cwd = src_root }):wait(1000)
  if obj.code == 0 then
    out.commit = vim.trim(obj.stdout or "")
  else
    out.commit = "unknown"
  end
  return out
end

---@enum obsidian.runtime.OSType
M.OSType = {
  Linux = "Linux",
  Wsl = "Wsl",
  Windows = "Windows",
  Darwin = "Darwin",
  FreeBSD = "FreeBSD",
}

---@type obsidian.runtime.OSType?
M._current_os = nil

---Get the running operating system.
---Reference https://vi.stackexchange.com/a/2577/33116
---@return obsidian.runtime.OSType
M.get_os = function()
  if M._current_os ~= nil then
    ---@diagnostic disable-next-line: return-type-mismatch
    return M._current_os
  end

  ---@type obsidian.runtime.OSType
  local this_os
  if vim.fn.has "win32" == 1 then
    this_os = M.OSType.Windows
  else
    local uname = assert(vim.uv.os_uname())
    local sysname = uname.sysname
    local release = uname.release:lower()
    if sysname:lower() == "linux" and string.find(release, "microsoft") then
      this_os = M.OSType.Wsl
    else
      ---@cast sysname obsidian.runtime.OSType
      this_os = sysname
    end
  end

  M._current_os = this_os
  return this_os
end

return M
