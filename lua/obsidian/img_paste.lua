local Path = require "obsidian.path"
local log = require "obsidian.log"
local run_job = require("obsidian.async").run_job
local api = require "obsidian.api"
local util = require "obsidian.util"

local M = {}

local img_types = {
  ["image/jpeg"] = "jpeg",
  ["image/png"] = "png",
  ["image/avif"] = "avif",
  ["image/webp"] = "webp",
  ["image/bmp"] = "bmp",
  ["image/gif"] = "gif",
}

-- Image pasting adapted from https://github.com/ekickx/clipboard-image.nvim

---@return string
local function get_clip_check_command()
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

local function get_image_type(content)
  for _, line in ipairs(content) do
    if img_types[line] then
      return img_types[line]
    end
  end
  return nil
end

--- Get the type of image on the clipboard.
---
---@return "png"|"jpeg"|nil
function M.get_clipboard_img_type()
  local check_cmd = get_clip_check_command()
  local result_string = vim.fn.system(check_cmd)
  local content = vim.split(result_string, "\n")

  local is_img = false
  -- See: [Data URI scheme](https://en.wikipedia.org/wiki/Data_URI_scheme)
  local this_os = api.get_os()
  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    if vim.tbl_contains(content, "text/uri-list") then
      local success =
        os.execute "wl-paste --type text/uri-list | sed 's|file://||' | head -n1 | tr -d '[:space:]' | xargs -I{} sh -c 'wl-copy < \"$1\"' _ {}"
      if success == 0 then
        -- Re-check for image type after potential conversion
        result_string = vim.fn.system(check_cmd)
        content = vim.split(result_string, "\n")
        return get_image_type(content)
      end
    else
      return get_image_type(content)
    end

  -- Code for non-Linux Operating systems (only supports png)
  elseif this_os == api.OSType.Darwin then
    is_img = string.sub(content[1], 1, 9) == "iVBORw0KG" -- Magic png number in base64
    if is_img then
      return "png"
    end
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    is_img = content ~= nil
    if is_img then
      return "png"
    end
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
  return nil
end

--- TODO: refactor Windows with run_job?

--- Save image from clipboard to `path`.
---@param path string
---@param img_type "png" | "jpeg"
---
---@return boolean|integer|? result
local function save_clipboard_image(path, img_type)
  local this_os = api.get_os()

  if this_os == api.OSType.Linux or this_os == api.OSType.FreeBSD then
    local mime_type = "image/" .. img_type
    local cmd
    local display_server = os.getenv "XDG_SESSION_TYPE"
    if display_server == "x11" or display_server == "tty" then
      cmd = string.format("xclip -selection clipboard -t %s -o > '%s'", mime_type, path)
      return run_job { "bash", "-c", cmd }
    elseif display_server == "wayland" then
      cmd = string.format("wl-paste --no-newline --type %s > %s", mime_type, vim.fn.shellescape(path))
      return run_job { "bash", "-c", cmd }
    end
  elseif this_os == api.OSType.Windows or this_os == api.OSType.Wsl then
    local cmd = 'powershell.exe -c "'
      .. string.format("(get-clipboard -format image).save('%s', 'png')", string.gsub(path, "/", "\\"))
      .. '"'
    return os.execute(cmd)
  elseif this_os == api.OSType.Darwin then
    return run_job { "pngpaste", path }
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
end

--- @param path string image_path The absolute path to the image file.
--- @return string
M.paste = function(path, img_type)
  if util.contains_invalid_characters(path) then
    log.warn "Links will not work with file names containing any of these characters in Obsidian: # ^ [ ] |"
  end

  ---@diagnostic disable-next-line: cast-local-type
  path = Path.new(path)

  -- If there is no suffix provided, append it
  if not path.suffix then
    ---@diagnostic disable-next-line: cast-local-type
    path = path:with_suffix("." .. img_type)

  -- If user appends their own suffix, check if it is valid based on img_type
  elseif not (path.suffix == "." .. img_type or (img_type == "jpeg" and path.suffix == ".jpg")) then
    local expected_suffix = (img_type == "jpeg") and ".jpeg' or '.jpg" or "." .. img_type
    return log.err("invalid suffix for image name '%s', must be '%s'", path.suffix, expected_suffix)
  end

  if Obsidian.opts.attachments.confirm_img_paste then
    -- Get confirmation from user.
    if not api.confirm("Saving image to '" .. tostring(path) .. "'. Do you want to continue?") then
      return log.warn "Paste aborted"
    end
  end

  -- Ensure parent directory exists.
  assert(path:parent()):mkdir { exist_ok = true, parents = true }

  -- Paste image.
  local result = save_clipboard_image(tostring(path), img_type)
  if result == false then
    log.err "Failed to save image"
    return
  end

  local img_text = Obsidian.opts.attachments.img_text_func(path)
  return img_text
end

return M
