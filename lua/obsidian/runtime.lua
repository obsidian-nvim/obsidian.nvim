local M = {}

local source = debug.getinfo(1, "S").source
local plugin_dir
if source:sub(1, 1) == "@" then
  local dir = vim.fs.dirname
  local path = vim.fs.normalize(vim.fs.abspath(source:sub(2)), { expand_env = false })
  plugin_dir = dir(dir(dir(path)))
end

--- Get the directory containing this plugin's Lua module.
---@return string?
M.get_plugin_dir = function()
  return plugin_dir
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
    local uname = vim.uv.os_uname()
    if not uname then
      return M.OSType.Linux -- HACK:
    end
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
