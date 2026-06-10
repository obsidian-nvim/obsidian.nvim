local api = require "obsidian.api"

---Text-oriented system clipboard access (mime type listing, html retrieval).
---Image clipboard handling lives in obsidian.img_paste.
local M = {}

---@return "x11"|"wayland"|? display server
local function display_server()
  local session = os.getenv "XDG_SESSION_TYPE"
  if session == "x11" or session == "tty" then
    return "x11"
  elseif session == "wayland" then
    return "wayland"
  end

  -- XDG_SESSION_TYPE is often unset (e.g. under WSLg)
  if os.getenv "WAYLAND_DISPLAY" then
    return "wayland"
  elseif os.getenv "DISPLAY" then
    return "x11"
  end
end

---Resolve the powershell executable. On WSL the Windows PATH may not be
---appended (interop appendWindowsPath=false), so fall back to the absolute path.
---@return string|?
local function powershell_exe()
  if vim.fn.executable "powershell.exe" == 1 then
    return "powershell.exe"
  end

  local abs = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  if api.get_os() == api.OSType.Wsl and vim.uv.fs_stat(abs) then
    return abs
  end
end

---@param cmd string[]
---@return string|? stdout on success
local function system(cmd)
  local ok, out = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok or out.code ~= 0 or not out.stdout or out.stdout == "" then
    return nil
  end
  return out.stdout
end

---List clipboard mime types with the native (wayland/x11) tools, when both a
---display server and the matching tool are available.
---@return string|?
local function native_list_types()
  local ds = display_server()
  if ds == "x11" and vim.fn.executable "xclip" == 1 then
    return system { "xclip", "-selection", "clipboard", "-o", "-t", "TARGETS" }
  elseif ds == "wayland" and vim.fn.executable "wl-paste" == 1 then
    return system { "wl-paste", "--list-types" }
  end
end

---Get clipboard html with the native (wayland/x11) tools.
---@return string|?
local function native_get_html()
  local ds = display_server()
  if ds == "x11" and vim.fn.executable "xclip" == 1 then
    return system { "xclip", "-selection", "clipboard", "-o", "-t", "text/html" }
  elseif ds == "wayland" and vim.fn.executable "wl-paste" == 1 then
    return system { "wl-paste", "--no-newline", "--type", "text/html" }
  end
end

---@return string|? raw CF_HTML payload
local function powershell_get_html()
  local exe = powershell_exe()
  if not exe then
    return nil
  end
  return system { exe, "-NoProfile", "-Command", "Get-Clipboard -TextFormatType Html" }
end

---List the mime types / formats currently on the system clipboard.
---
---@return string[]
M.list_types = function()
  local this_os = api.get_os()
  local out

  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    out = native_list_types()
  elseif this_os == api.OSType.Darwin then
    out = system { "osascript", "-e", "clipboard info" }
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    -- WSLg ships its own wayland/x11 clipboard bridge, prefer it
    out = native_list_types()
    if not out then
      -- powershell has no direct format listing; probe for html
      local html = powershell_get_html()
      if html and html:find "<" then
        return { "text/html" }
      end
      return {}
    end
  end

  if not out then
    return {}
  end

  if this_os == api.OSType.Darwin then
    -- `clipboard info` returns a comma separated list like:
    -- «class HTML», 1416, «class utf8», 100, string, 100
    local types = {}
    for class in out:gmatch "«class (%w+)»" do
      table.insert(types, class)
    end
    if out:find "string" then
      table.insert(types, "string")
    end
    return types
  end

  return vim.split(vim.trim(out), "\n")
end

---Whether the system clipboard currently holds HTML content.
---
---@return boolean
M.has_html = function()
  local this_os = api.get_os()
  local types = M.list_types()

  if this_os == api.OSType.Darwin then
    return vim.list_contains(types, "HTML")
  end

  return vim.list_contains(types, "text/html")
end

---Decode the hex payload of an AppleScript `«data HTML...»` clipboard record.
---
---@param out string
---@return string|?
local function decode_osascript_html(out)
  local hex = out:match "«data HTML(%x+)»"
  if not hex then
    return nil
  end
  return (hex:gsub("%x%x", function(byte)
    return string.char(tonumber(byte, 16))
  end))
end

---Extract the fragment from windows CF_HTML clipboard payloads, which wrap
---the html in a header (Version, StartHTML, ...) and fragment markers.
---
---@param out string
---@return string|?
local function decode_cf_html(out)
  local fragment = out:match "<!%-%-StartFragment%-%->(.-)<!%-%-EndFragment%-%->"
  if fragment then
    return fragment
  end
  local start = out:find("<", 1, true)
  return start and out:sub(start) or nil
end

---Get the HTML content of the system clipboard, if any.
---
---@return string|?
M.get_html = function()
  local this_os = api.get_os()

  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    return native_get_html()
  elseif this_os == api.OSType.Darwin then
    local out = system { "osascript", "-e", "the clipboard as «class HTML»" }
    return out and decode_osascript_html(out) or nil
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    local out = native_get_html()
    if out then
      return out
    end
    out = powershell_get_html()
    return out and decode_cf_html(out) or nil
  end

  return nil
end

---Get the plain text content of the system clipboard.
---
---@return string|?
M.get_text = function()
  local text = vim.fn.getreg "+"
  if text == nil or text == "" then
    return nil
  end
  return text
end

return M
