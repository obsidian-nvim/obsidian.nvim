local api = require "obsidian.api"
local Clipboard = require "obsidian.clipboard"

local H = {}

local attachment_types = {
  ["image/jpeg"] = "jpeg",
  ["image/png"] = "png",
  ["image/avif"] = "avif",
  ["image/webp"] = "webp",
  ["image/bmp"] = "bmp",
  ["image/gif"] = "gif",
}

local function get_attachment_type(content)
  for _, line in ipairs(content) do
    if attachment_types[line] then
      -- return attachment_types[line]
      return line
    end
  end
  return nil
end

H[api.OSType.Linux] = function(content)
  if vim.tbl_contains(content, "text/uri-list") then
    local success =
      os.execute "wl-paste --type text/uri-list | sed 's|file://||' | head -n1 | tr -d '[:space:]' | xargs -I{} sh -c 'wl-copy < \"$1\"' _ {}"
    if success == 0 then
      -- Re-check for image type after potential conversion NOTE: why?
      local result_string = vim.fn.system(Clipboard.get_check_command())
      content = vim.split(result_string, "\n")
      return get_attachment_type(content)
    end
  else
    return get_attachment_type(content)
  end
end

H[api.OSType.FreeBSD] = H[api.OSType.Linux]

-- Following systems only support png

H[api.OSType.Darwin] = function(content)
  local is_img = string.sub(content[1], 1, 9) == "iVBORw0KG" -- Magic png number in base64
  if is_img then
    return "image/png"
  end
end

H[api.OSType.Windows] = function(content)
  local is_img = content ~= nil
  if is_img then
    return "image/png"
  end
end

H[api.OSType.Wsl] = H[api.OSType.Windows]

--- Get the type of image on the clipboard.
---
---@return "image/png"|"image/jpeg"|nil
return function()
  local check_cmd = Clipboard.get_check_command()
  local result_string = vim.fn.system(check_cmd)
  local content = vim.split(result_string, "\n")

  -- See: [Data URI scheme](https://en.wikipedia.org/wiki/Data_URI_scheme)
  local this_os = api.get_os()
  if H[this_os] then
    return H[this_os](content)
  else
    error("image saving not implemented for OS '" .. this_os .. "'")
  end
end
