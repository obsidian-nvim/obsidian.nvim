local api = require "obsidian.api"
local M = {}
local CLIPBOARD_ERROR = "no shell commands available for clipboard integration, check `checkhealth obsidian"

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

---@return string
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

---check cmd lists the types of content in the clipboard TODO: not specific to image on other platforms
---@return string[]|?
function M._get_list_command()
  local this_os = api.get_os()
  if this_os == "Linux" or this_os == "FreeBSD" then
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      -- check_cmd = "xclip -selection clipboard -o -t TARGETS"
      return { "xclip", "-selection", "clipboard", "-o", "-t", "TARGETS" }
    elseif display_server == "wayland" then
      return { "wl-paste", "--list-types" }
    end
  elseif this_os == api.OSType.Darwin then
    -- check_cmd = "pngpaste -b 2>&1"
    return { "pngpaste", "-b", "2>&1" } -- TODO:?
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    return { "powershell.exe", '"Get-Clipboard -Format Image"' }
  end
end

---@return string[]|?
function M.list_types()
  local cmds = assert(M._get_list_command(), CLIPBOARD_ERROR)
  local out = vim.system(cmds):wait()
  if out.code ~= 0 then
    return
  end
  return vim.split(out.stdout, "\n", { trimempty = true })
end

---@param mime_type obsidian.mimetypes
---@return string[]|?
function M.get_get_command(mime_type)
  local this_os = api.get_os()
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      return
      -- check_cmd = "xclip -selection clipboard -o -t TARGETS"
    elseif display_server == "wayland" then
      return { "wl-paste", "--type", mime_type }
    end
  elseif this_os == api.OSType.Darwin then
    return
    -- cmd = "pngpaste -b 2>&1"
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    return
    -- cmd = 'powershell.exe "Get-Clipboard -Format Image"'
  end
end

function M.get_content(mime_type)
  local cmds = assert(M.get_get_command(mime_type), CLIPBOARD_ERROR)
  local out = vim.system(cmds):wait()
  if out.code ~= 0 then
    return
  end
  -- TODO: might be different per platform
  return vim.split(out.stdout, "\n", { trimempty = true })
end

return M
