local api = require "obsidian.api"
local run_job = require("obsidian.async").run_job

local save_handlers = {}

save_handlers[api.OSType.Linux] = function(path, mime_type)
  local cmd
  local display_server = os.getenv "XDG_SESSION_TYPE"
  if display_server == "x11" or display_server == "tty" then
    cmd = string.format("xclip -selection clipboard -t %s -o > '%s'", mime_type, path)
  elseif display_server == "wayland" then
    cmd = string.format("wl-paste --no-newline --type %s > %s", mime_type, vim.fn.shellescape(path))
  end
  return run_job { "bash", "-c", cmd }
end

save_handlers[api.OSType.FreeBSD] = save_handlers[api.OSType.Linux]

save_handlers[api.OSType.Windows] = function(path, mime_type)
  local cmd = 'powershell.exe -c "'
    .. string.format("(get-clipboard -format image).save('%s', 'png')", string.gsub(path, "/", "\\"))
    .. '"' -- NOTE: change format image
  return os.execute(cmd) -- NOTE: use vim.system?
end

save_handlers[api.OSType.Wsl] = save_handlers[api.OSType.Windows]

save_handlers[api.OSType.Darwin] = function(path, mime_type)
  return run_job { "pngpaste", path }
end

--- Save image from clipboard to `path`.
---@param path string
---@param mime_type "png" | "jpeg"
---
---@return boolean|integer|? result
return function(path, mime_type)
  local this_os = api.get_os()

  if save_handlers[this_os] then
    save_handlers[this_os](path, mime_type)
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
end
