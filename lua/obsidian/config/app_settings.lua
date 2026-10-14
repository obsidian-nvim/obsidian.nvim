local log = require "obsidian.log"
local M = {}

---Read a native settings file without modifying it.
---@param path string
---@param allow_list? boolean
---@return table?, boolean?
local function read_json(path, allow_list)
  local file, err = io.open(path, "r")
  if not file then
    if vim.uv.fs_stat(path) then
      log.warn_once("Unable to read Obsidian settings '%s': %s", path, err)
    end
    return
  end
  local text, read_err = file:read "*a"
  file:close()
  if not text then
    log.warn_once("Unable to read Obsidian settings '%s': %s", path, read_err)
    return
  end
  text = text:gsub("^\239\187\191", "")
  local ok, data = pcall(vim.json.decode, text)
  local object = text:match "^%s*{"
  local list = allow_list and text:match "^%s*%["
  if not ok or type(data) ~= "table" or not (object or list) then
    log.warn_once(
      "Invalid Obsidian settings in '%s': expected a JSON %s",
      path,
      allow_list and "object or array" or "object"
    )
    return
  end
  return data, list ~= nil and list ~= false
end

---@param data table
---@param key string
---@param default string|boolean
---@param path string
---@return string|boolean
local function value(data, key, default, path)
  local result = data[key]
  if result == nil or result == vim.NIL then
    return default
  elseif type(result) ~= type(default) then
    log.warn_once("Invalid Obsidian setting '%s' in '%s': expected %s", key, path, type(default))
    return default
  end
  return result
end

---@param data table
---@param key string
---@param default string
---@param path string
---@return string
local function string_value(data, key, default, path)
  local result = value(data, key, default, path)
  ---@cast result string
  return result
end

---Convert a vault-relative app path, preserving note-relative attachment paths.
---@param data table
---@param key string
---@param path string
---@param default? string
---@param note_relative? boolean
---@return string
local function folder(data, key, path, default, note_relative)
  local fallback = default == "/" and "" or default or ""
  local result = string_value(data, key, default or "", path):gsub("\\", "/")
  if result == "/" then
    return ""
  end
  if result:match "^/" or result:match "^%a:" then
    log.warn_once("Invalid Obsidian setting '%s' in '%s': expected a vault-relative path", key, path)
    return fallback
  end
  for part in result:gmatch "[^/]+" do
    if part == ".." then
      log.warn_once("Invalid Obsidian setting '%s' in '%s': path leaves the vault", key, path)
      return fallback
    end
  end
  if note_relative and (result == "." or vim.startswith(result, "./")) then
    return result
  end
  return (result:gsub("^%./", ""))
end

---@param data table
---@param path string
---@return string, string
local function note_location(data, path)
  local location = string_value(data, "newFileLocation", "root", path)
  if location == "folder" then
    return "notes_subdir", folder(data, "newFileFolderPath", path)
  elseif location == "current" then
    return "current_dir", ""
  end
  if location ~= "root" then
    log.warn_once("Invalid Obsidian setting 'newFileLocation' in '%s': %s", path, location)
  end
  return "notes_subdir", ""
end

---@param root string
---@param data table
---@param path string
---@return string|vim.NIL
local function template_path(root, data, path)
  local template = folder(data, "template", path)
  if template == "" then
    return vim.NIL
  end
  return vim.fs.joinpath(root, template)
end

---Map supported app settings. Missing files leave Lua options unchanged;
---missing keys in a valid file use the app's defaults.
---@param root string|obsidian.Path
---@param config_dir? string
---@return table<string, any>
M.read = function(root, config_dir)
  root = tostring(root)
  local dir = vim.fs.joinpath(root, config_dir or ".obsidian")
  local app_path = vim.fs.joinpath(dir, "app.json")
  local app = read_json(app_path)
  ---@type table<string, any>
  local opts = {}
  if app then
    local location, subdir = note_location(app, app_path)
    local format = string_value(app, "newLinkFormat", "shortest", app_path)
    if not vim.list_contains({ "shortest", "relative", "absolute" }, format) then
      log.warn_once("Invalid Obsidian setting 'newLinkFormat' in '%s': %s", app_path, format)
      format = "shortest"
    end
    opts.new_notes_location = location
    opts.notes_subdir = subdir
    opts.attachments = { folder = folder(app, "attachmentFolderPath", app_path, "/", true) }
    opts.link = {
      style = value(app, "useMarkdownLinks", false, app_path) and "markdown" or "wiki",
      format = format,
      auto_update = value(app, "alwaysUpdateLinks", false, app_path),
    }
  end

  local templates_path = vim.fs.joinpath(dir, "templates.json")
  local templates = read_json(templates_path)
  if templates then
    local template_folder = folder(templates, "folder", templates_path)
    opts.templates = {
      folder = template_folder ~= "" and template_folder or vim.NIL,
      date_format = string_value(templates, "dateFormat", "YYYY-MM-DD", templates_path),
      time_format = string_value(templates, "timeFormat", "HH:mm", templates_path),
    }
    if opts.templates.date_format == "" then
      opts.templates.date_format = "YYYY-MM-DD"
    end
    if opts.templates.time_format == "" then
      opts.templates.time_format = "HH:mm"
    end
  end

  -- Empty daily/unique folders use the app's default new-note location.
  -- The app supplies no current file in this case, so 'current' falls back to root.
  local default_folder = ""
  if app and string_value(app, "newFileLocation", "root", app_path) == "folder" then
    default_folder = folder(app, "newFileFolderPath", app_path)
  end
  for name, section in pairs { ["daily-notes"] = "daily_notes", ["zk-prefixer"] = "unique_note" } do
    local path = vim.fs.joinpath(dir, name .. ".json")
    local data = read_json(path)
    if data then
      local format = string_value(data, "format", name == "daily-notes" and "YYYY-MM-DD" or "YYYYMMDDHHmm", path)
      if format == "" then
        format = name == "daily-notes" and "YYYY-MM-DD" or "YYYYMMDDHHmm"
      end
      local note_folder = folder(data, "folder", path)
      local explicit_root = string_value(data, "folder", "", path) == "/"
      opts[section] = {
        folder = (note_folder ~= "" or explicit_root) and note_folder or default_folder,
        template = template_path(root, data, path),
      }
      opts[section][name == "daily-notes" and "date_format" or "format"] = format
    end
  end

  local core_path = vim.fs.joinpath(dir, "core-plugins.json")
  local core, is_list = read_json(core_path, true)
  if core then
    for id, section in pairs { templates = "templates", ["daily-notes"] = "daily_notes", ["zk-prefixer"] = "unique_note" } do
      local enabled = is_list and vim.list_contains(core, id) or false
      if not is_list then
        local configured = value(core, id, id ~= "zk-prefixer", core_path)
        ---@cast configured boolean
        enabled = configured
      end
      opts[section] = opts[section] or {}
      opts[section].enabled = enabled
    end
  end
  return opts
end

return M
