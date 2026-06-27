local attachment = require "obsidian.attachment"
local util = require "obsidian.util"

local M = {}

---@class obsidian.IconSpec
---@field icon string
---@field hl_group string|?

---@type table<string, obsidian.IconSpec>
M.kinds = {
  missing = { icon = "󰝒", hl_group = "ObsidianMissingIcon" },
  missing_attachment = { icon = "󱫄" },
  bookmark = { icon = "" },
  note = { icon = "" },
  base = { icon = "󰆼" },
  canvas = { icon = "󰛟" },
  image = { icon = "󰋩" },
  audio = { icon = "󰎆" },
  video = { icon = "󰕧" },
  pdf = { icon = "" },
  folder = { icon = "󰉋" },
  search = { icon = "󰍉" },
  url = { icon = "" },
  file = { icon = "󰈙" },
}

---@type table<string, string[]>
M.extensions = {
  note = { "md", "markdown", "qmd" },
  base = { "base" },
  canvas = { "canvas" },
  image = { "avif", "bmp", "gif", "jpg", "jpeg", "png", "svg", "webp" },
  audio = { "flac", "m4a", "mp3", "ogg", "wav", "3gp" },
  video = { "mkv", "mov", "mp4", "ogv", "webm" },
  pdf = { "pdf" },
}

---@type table<string, obsidian.IconSpec>
M.by_extension = {}

---@type table<string, obsidian.IconSpec>
M.by_bookmark_type = {
  group = M.kinds.bookmark,
  search = M.kinds.search,
  url = M.kinds.url,
  folder = M.kinds.folder,
}

---@param kind string
---@param extensions string[]
local register_extensions = function(kind, extensions)
  local spec = M.kinds[kind]
  if not spec then
    error("unknown icon kind: " .. kind)
  end

  for _, ext in ipairs(extensions) do
    M.by_extension[ext:lower()] = spec
  end
end

for kind, extensions in pairs(M.extensions) do
  register_extensions(kind, extensions)
end

for _, ext in ipairs(attachment.filetypes) do
  M.by_extension[ext] = M.by_extension[ext] or M.kinds.file
end

M.by_filetype = M.by_extension

---@param path string
---@return string
M.extension = function(path)
  return (path:match "%.([^./\\]+)$" or ""):lower()
end

---@param path string
---@return boolean
local function is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

---@param path string
---@return obsidian.IconSpec
local spec_for_path = function(path)
  local is_uri = util.is_uri(path)
  if is_uri then
    return M.kinds.url
  elseif is_dir(path) then
    return M.kinds.folder
  end

  return M.by_extension[M.extension(path)] or M.kinds.file
end

---@param bookmark obsidian.Bookmark
---@return obsidian.IconSpec
local spec_for_bookmark = function(bookmark)
  if bookmark.type == "file" and (bookmark._path or bookmark.path) then
    return spec_for_path(bookmark._path or bookmark.path)
  end

  return M.by_bookmark_type[bookmark.type] or M.kinds.bookmark
end

---@param entry obsidian.PickerEntry|string
---@return obsidian.IconSpec
local spec_for_entry = function(entry)
  if type(entry) == "string" then
    return spec_for_path(entry)
  end

  ---@cast entry { filename: string|?, user_data: table|? }
  local user_data = entry.user_data
  if type(user_data) == "table" then
    if user_data.missing == true then
      if user_data.attachment then
        return M.kinds.missing_attachment
      else
        return M.kinds.missing
      end
    elseif type(user_data.type) == "string" and user_data.ctime ~= nil then
      return spec_for_bookmark(user_data)
    end
  end

  if entry.filename then
    return spec_for_path(entry.filename)
  elseif type(user_data) == "table" and user_data.attachment ~= true then
    return M.kinds.note
  end

  return M.kinds.file
end

---@param path string
---@return string icon
---@return string|? hl_group
M.get_path_icon = function(path)
  local spec = spec_for_path(path)
  return spec.icon, spec.hl_group
end

---@param bookmark obsidian.Bookmark
---@return string icon
---@return string|? hl_group
M.get_bookmark_icon = function(bookmark)
  local spec = spec_for_bookmark(bookmark)
  return spec.icon, spec.hl_group
end

---@param entry obsidian.PickerEntry|string
---@return string icon
---@return string|? hl_group
M.get_icon = function(entry)
  local spec = spec_for_entry(entry)
  return spec.icon, spec.hl_group
end

return M
