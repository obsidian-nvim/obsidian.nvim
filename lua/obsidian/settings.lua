local api = require "obsidian.api"
local Path = require "obsidian.path"
local M = {}

-- TODO: read app.json
-- newLinkFormat
-- newFileLocation
-- useMarkdownLinks
-- attachmentsFolderPath

-- in the future:
-- autoConvertHtml -> Obsidian paste
-- note composer stuff
-- pdfExportSettings
-- alwaysUpdateLinks

-- switcher.json -> switcher mod
-- {
--   "showExistingOnly": true,
--   "showAttachments": true,
--   "showAllFileTypes": false
-- }

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

--- Read and parse a JSON file, returning nil if file doesn't exist or is invalid
---@param filepath obsidian.Path
---@return table|?
local function read_json(filepath)
  if not filepath:exists() then
    return nil
  end

  local f = io.open(tostring(filepath), "r")
  if not f then
    return nil
  end

  local success, result = pcall(function()
    local str = f:read "*a"
    f:close()
    return vim.json.decode(str)
  end)

  if not success or not result then
    pcall(function()
      f:close()
    end)
    return nil
  end

  return result
end

--- Read daily notes configuration from vault's .obsidian/daily-notes.json
---@param vault_root obsidian.Path
---@return obsidian.config.DailyNotesOpts|?
local read_daily_notes_config = function(vault_root)
  local config_file = vault_root / ".obsidian" / "daily-notes.json"
  local data = read_json(config_file)

  if not data then
    return nil
  end

  return {
    folder = data.folder,
    template = data.template, -- TODO: can no suffix be properly resolved?
    date_format = data.format,
  }
end

--- Read templates configuration from vault's .obsidian/templates.json
---@param vault_root obsidian.Path
---@return obsidian.config.TemplateOpts|?
local read_templates_config = function(vault_root)
  local data = read_json(vault_root / ".obsidian" / "templates.json")

  if not data then
    return nil
  end

  return {
    folder = data.folder,
    date_format = data.dateFormat,
    time_format = data.timeFormat,
  }
end

--- Read ZK prefixer configuration from vault's .obsidian/zk-prefixer.json
-- ---@param vault_root obsidian.Path
-- ---@return obsidian.config.UniqueNoteCreatorOpts|?
-- local read_zk_prefixer_config = function(vault_root)
--   local config_file = vault_root / ".obsidian" / "zk-prefixer.json"
--   local data = read_json(config_file)
--
--   if not data then
--     return nil
--   end
--
--   return {
--     folder = data.folder,
--     template = data.template,
--     format = data.format,
--   }
-- end

--- Read all vault settings from the .obsidian directory
---@param vault_root obsidian.Path
---@return obsidian.config
M.get_vault_config = function(vault_root)
  return {
    daily_notes = read_daily_notes_config(vault_root),
    templates = read_templates_config(vault_root),
  }
end

return M
