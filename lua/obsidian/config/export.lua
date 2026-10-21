local Path = require "obsidian.path"
local M = {}

local core_plugins = { templates = "templates", ["daily-notes"] = "daily_notes", ["zk-prefixer"] = "unique_note" }

---Read existing settings strictly so an export never discards malformed data.
---@param path string
---@param allow_list? boolean
---@return table, boolean
local function read_existing(path, allow_list)
  local file, err = io.open(path, "r")
  if not file then
    local _, _, code = vim.uv.fs_stat(path)
    if code == "ENOENT" then
      return vim.empty_dict(), false
    end
    error(("Unable to read Obsidian settings '%s': %s"):format(path, err), 0)
  end
  local text, read_err = file:read "*a"
  file:close()
  if not text then
    error(("Unable to read Obsidian settings '%s': %s"):format(path, read_err), 0)
  end
  text = text:gsub("^\239\187\191", "")
  local ok, data = pcall(vim.json.decode, text)
  local object = text:match "^%s*{"
  local list = allow_list and text:match "^%s*%["
  if not ok or type(data) ~= "table" or not (object or list) then
    error(
      ("Invalid Obsidian settings in '%s': expected a JSON %s"):format(
        path,
        allow_list and "object or array" or "object"
      ),
      0
    )
  end
  return data, list ~= nil and list ~= false
end

---Resolve shared paths from the vault, independently of Neovim's working directory.
---@param root obsidian.Path
---@param value string|obsidian.Path|nil
---@param field string
---@param note_relative? boolean
---@return string
local function relative_path(root, value, field, note_relative)
  local path = value and tostring(value):gsub("\\", "/") or ""
  if path == "" or path == "/" then
    return ""
  end
  if note_relative and (path == "." or vim.startswith(path, "./")) then
    for part in path:gmatch "[^/]+" do
      if part == ".." then
        error(field .. " cannot contain '..' in a note-relative path", 0)
      end
    end
    return path
  end
  local resolved = Path.new(path)
  if not resolved:is_absolute() then
    resolved = root / resolved
  end
  resolved = resolved:resolve()
  if resolved == root then
    return ""
  end
  local ok, relative = pcall(resolved.relative_to, resolved, root)
  if not ok then
    error(field .. " must resolve to a path inside the vault", 0)
  end
  return tostring(relative)
end

---@param root obsidian.Path
---@param opts obsidian.config.Internal
---@param value string|nil
---@param field string
---@return string
local function template_path(root, opts, value, field)
  if value == nil or value == "" then
    return ""
  end
  local path = Path.new(value)
  if not path:is_absolute() then
    local base = Path.new(opts.templates.folder or "")
    if not base:is_absolute() then
      base = root / base
    end
    path = base / path
  end
  local relative = relative_path(root, path, field)
  if not vim.endswith(relative, ".md") then
    relative = relative .. ".md"
  end
  return relative
end

---@param value string|function|nil
---@param field string
---@return string
local function moment_format(value, field)
  if type(value) ~= "string" or value == "" or value:find "%%" then
    error(field .. " must be a Moment-style format string to export to Obsidian", 0)
  end
  return value
end

---Build the complete export before opening any files for writing.
---@param workspace obsidian.Workspace
---@return table<string, table>, obsidian.config.Internal
local function shared_settings(workspace)
  local overrides = workspace.overrides or {}
  ---@cast overrides obsidian.config
  local opts = require("obsidian.config").normalize(overrides, Obsidian._opts)
  local root = workspace.root:resolve()
  local notes = relative_path(root, opts.notes_subdir, "notes_subdir")
  local templates = relative_path(root, opts.templates.folder, "templates.folder")
  if opts.templates.folder and templates == "" then
    error("templates.folder must name a non-root folder to round-trip through app settings", 0)
  end
  local daily = relative_path(root, opts.daily_notes.folder, "daily_notes.folder")
  local unique = relative_path(root, opts.unique_note.folder, "unique_note.folder")
  return {
    ["app.json"] = {
      newFileLocation = opts.new_notes_location == "current_dir" and "current" or (notes == "" and "root" or "folder"),
      newFileFolderPath = notes,
      attachmentFolderPath = relative_path(root, opts.attachments.folder, "attachments.folder", true):gsub("^$", "/"),
      useMarkdownLinks = opts.link.style == "markdown",
      newLinkFormat = opts.link.format,
      alwaysUpdateLinks = opts.link.auto_update,
    },
    ["templates.json"] = {
      folder = templates,
      dateFormat = moment_format(opts.templates.date_format, "templates.date_format"),
      timeFormat = moment_format(opts.templates.time_format, "templates.time_format"),
    },
    ["daily-notes.json"] = {
      -- '/' keeps an explicit root folder from inheriting the app's new-note folder.
      folder = daily ~= "" and daily or "/",
      format = moment_format(opts.daily_notes.date_format, "daily_notes.date_format"),
      template = template_path(root, opts, opts.daily_notes.template, "daily_notes.template"),
    },
    ["zk-prefixer.json"] = {
      folder = unique ~= "" and unique or "/",
      format = moment_format(opts.unique_note.format, "unique_note.format"),
      template = template_path(root, opts, opts.unique_note.template, "unique_note.template"),
    },
  },
    opts
end

---@class obsidian.config.ExportFile
---@field path string
---@field text string
---@field temporary? string

---Export shared Lua options for one workspace. Existing app values are not used
---as the source. Unknown keys and unrelated core plugins are preserved.
---All files are validated and staged before each destination is replaced atomically.
---@param workspace obsidian.Workspace
---@return string[] paths Written files.
M.write = function(workspace)
  local settings, opts = shared_settings(workspace)
  local dir = vim.fs.joinpath(tostring(workspace.root), opts.app_settings.config_dir or ".obsidian")
  ---@type obsidian.config.ExportFile[]
  local files = {}
  for _, name in ipairs { "app.json", "templates.json", "daily-notes.json", "zk-prefixer.json", "core-plugins.json" } do
    local path = vim.fs.joinpath(dir, name)
    local data, list = read_existing(path, name == "core-plugins.json")
    if name == "core-plugins.json" then
      for id, section in pairs(core_plugins) do
        if list then
          data = vim.tbl_filter(function(value)
            return value ~= id
          end, data)
          if opts[section].enabled then
            table.insert(data, id)
          end
        else
          data[id] = opts[section].enabled
        end
      end
    else
      for key, value in pairs(settings[name]) do
        data[key] = value
      end
    end
    table.insert(files, { path = path, text = vim.json.encode(data) .. "\n" })
  end

  vim.fn.mkdir(dir, "p")
  local ok, err = pcall(function()
    for _, file in ipairs(files) do
      local fd, temporary = vim.uv.fs_mkstemp(file.path .. ".XXXXXX")
      if not fd then
        error(("Unable to stage '%s': %s"):format(file.path, temporary), 0)
      end
      file.temporary = temporary
      local written, write_err = vim.uv.fs_write(fd, file.text, 0)
      local closed, close_err = vim.uv.fs_close(fd)
      if written ~= #file.text or not closed then
        error(("Unable to stage '%s': %s"):format(file.path, write_err or close_err or "incomplete write"), 0)
      end
    end
    for _, file in ipairs(files) do
      local renamed, rename_err = vim.uv.fs_rename(assert(file.temporary, "Export file was not staged"), file.path)
      if not renamed then
        error(("Unable to replace '%s': %s; earlier files may already be updated"):format(file.path, rename_err), 0)
      end
      file.temporary = nil
    end
  end)
  for _, file in ipairs(files) do
    if file.temporary then
      vim.uv.fs_unlink(file.temporary)
    end
  end
  if not ok then
    error(err, 0)
  end
  return vim.tbl_map(function(file)
    return file.path
  end, files)
end

return M
