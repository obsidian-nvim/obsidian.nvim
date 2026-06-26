local attachment = require "obsidian.attachment"

local M = {}

---@class obsidian.IconSpec
---@field icon string
---@field hl_group string|?

---@type table<string, obsidian.IconSpec>
M.kinds = {
  missing = { icon = "󰝒", hl_group = "ObsidianMissingIcon" },
  missing_attachment = { icon = "󱫄" },
  note = { icon = "" },
  canvas = { icon = "󰛟" },
  image = { icon = "󰋩" },
  audio = { icon = "󰎆" },
  video = { icon = "󰕧" },
  pdf = { icon = "" },
  file = { icon = "󰈙" },
}

---@type table<string, obsidian.IconSpec>
local by_filetype = {
  md = M.kinds.note,
  markdown = M.kinds.note,
  qmd = M.kinds.note,
  base = M.kinds.note,
  canvas = M.kinds.canvas,

  avif = M.kinds.image,
  bmp = M.kinds.image,
  gif = M.kinds.image,
  jpg = M.kinds.image,
  jpeg = M.kinds.image,
  png = M.kinds.image,
  svg = M.kinds.image,
  webp = M.kinds.image,

  flac = M.kinds.audio,
  m4a = M.kinds.audio,
  mp3 = M.kinds.audio,
  ogg = M.kinds.audio,
  wav = M.kinds.audio,
  ["3gp"] = M.kinds.audio,

  mkv = M.kinds.video,
  mov = M.kinds.video,
  mp4 = M.kinds.video,
  ogv = M.kinds.video,
  webm = M.kinds.video,

  pdf = M.kinds.pdf,
}

for _, ext in ipairs(attachment.filetypes) do
  by_filetype[ext] = by_filetype[ext] or M.kinds.file
end

M.by_filetype = by_filetype

---@param path string
---@return string
local function extension(path)
  return (path:match "%.([^./]+)$" or ""):lower()
end

---@param entry obsidian.PickerEntry|string
---@return string|?
local function entry_path(entry)
  if type(entry) == "string" then
    return entry
  end

  if entry.filename then
    return entry.filename
  end

  local text = entry.text
  if type(text) == "string" then
    text = text:gsub("%s+|%s+.*$", ""):gsub("%s+%(create%)$", "")
    return text
  end

  if type(entry.user_data) == "string" then
    return entry.user_data
  end
end

---@param entry obsidian.PickerEntry|string
---@return string icon
---@return string|? hl_group
M.get_icon = function(entry)
  if type(entry) == "table" then
    local user_data = entry.user_data
    if type(user_data) == "table" and user_data.missing == true then
      if user_data.attachment then
        return M.kinds.missing_attachment.icon, M.kinds.missing_attachment.hl_group
      else
        return M.kinds.missing.icon, M.kinds.missing.hl_group
      end
    end
  end

  local path = entry_path(entry)
  local spec = path and by_filetype[extension(path)]
  if not spec and type(entry) == "table" then
    local user_data = entry.user_data
    if type(user_data) == "table" and user_data.attachment ~= true then
      spec = M.kinds.note
    end
  end
  spec = spec or M.kinds.file

  return spec.icon, spec.hl_group
end

---@param entry obsidian.PickerEntry
---@return string
M.format_picker_entry = function(entry)
  local icon = M.get_icon(entry)
  local text = entry.text or entry.filename or ""
  if text == "" then
    return icon
  end
  return icon .. " " .. text
end

return M
