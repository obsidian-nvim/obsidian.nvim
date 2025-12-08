local api = require "obsidian.api"
local M = {}

---@alias obsidian.mimetypes
---| "text/markdown"
---| "application/octet-stream"
---| "application/json"
---| "image/avif"
---| "image/bmp"
---| "image/gif"
---| "image/jpeg"
---| "image/png"
---| "image/svg+xml"
---| "image/webp"
---| "audio/flac"
---| "audio/mp4"
---| "audio/mpeg"
---| "audio/ogg"
---| "audio/wav"
---| "audio/webm"
---| "video/3gpp"
---| "video/x-matroska"
---| "video/quicktime"
---| "video/mp4"
---| "video/ogg"
---| "video/webm"
---| "application/pdf"

---@return string TODO: a list of commands?
function M.get_check_command()
  local check_cmd
  local this_os = api.get_os()
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      check_cmd = "xclip -selection clipboard -o -t TARGETS"
    elseif display_server == "wayland" then
      check_cmd = "wl-paste --list-types"
    end
  elseif this_os == api.OSType.Darwin then
    check_cmd = "pngpaste -b 2>&1"
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    check_cmd = 'powershell.exe "Get-Clipboard -Format Image"'
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
  return check_cmd
end

---@param mime_type obsidian.mimetypes
---@return string  TODO: a list of commands?
function M.get_get_command(mime_type)
  local cmd
  local this_os = api.get_os()
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      -- check_cmd = "xclip -selection clipboard -o -t TARGETS"
    elseif display_server == "wayland" then
      cmd = string.format("wl-paste --type %s", mime_type)
    end
  elseif this_os == api.OSType.Darwin then
    -- cmd = "pngpaste -b 2>&1"
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    -- cmd = 'powershell.exe "Get-Clipboard -Format Image"'
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
  return cmd
end

return M
