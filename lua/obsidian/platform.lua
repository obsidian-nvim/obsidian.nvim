local M = {}

---@enum obsidian.platform.OSType
M.OSType = {
  Linux = "Linux",
  Wsl = "Wsl",
  Windows = "Windows",
  Darwin = "Darwin",
  FreeBSD = "FreeBSD",
}

---@type obsidian.platform.OSType?
local current_os

--- Get the running operating system, distinguishing WSL from native Linux.
--- Reference: https://vi.stackexchange.com/a/2577/33116
---@return obsidian.platform.OSType
function M.get_os()
  if current_os == nil then
    if vim.fn.has "win32" == 1 then
      current_os = M.OSType.Windows
    else
      local uname = vim.uv.os_uname()
      local sysname = uname.sysname
      if sysname:lower() == "linux" and uname.release:lower():find("microsoft", 1, true) then
        current_os = M.OSType.Wsl
      else
        ---@cast sysname obsidian.platform.OSType
        current_os = sysname
      end
    end
  end
  return current_os
end

return M
