local api = require "obsidian.api"
local Path = require "obsidian.path"
local M = {}

---@return obsidian.Path
local function global_config_dir()
  local current_os = api.get_os()
  local path

  if current_os == "Darwin" then
    local home = os.getenv "HOME"
    assert(home, "HOME not set")
    path = home .. "/Library/Application Support/obsidian"
  elseif current_os == "Windows" then
    local appdata = os.getenv "APPDATA"
    assert(appdata, "APPDATA not set")
    path = appdata .. "\\Obsidian"
  else
    -- Linux and other Unix-like systems
    local xdg = os.getenv "XDG_CONFIG_HOME"
    if xdg and xdg ~= "" then
      path = xdg .. "/obsidian"
    else
      local home = os.getenv "HOME"
      assert(home, "HOME not set")
      path = home .. "/.config/obsidian"
    end
  end
  return Path.new(path)
end

---@return obsidian.workspace.WorkspaceSpec[]
M.get_workspaces_from_global_config = function()
  local dir = global_config_dir()
  if not dir:exists() then
    return {}
  end
  local settings_file = dir / "obsidian.json"
  if not settings_file:exists() then
    return {}
  end

  local f = io.open(tostring(settings_file), "r")
  assert(f, "settings file not found")
  local str = f:read "*a"
  f:close()
  local settings = vim.json.decode(str)
  local vaults = settings and settings.vaults and settings.vaults or {}
  local wss = {}
  for _, vault_setting in pairs(vaults) do
    wss[#wss + 1] = {
      path = vault_setting.path,
    }
  end
  return wss
end

--- TODO: get daily notes, template settings

return M
