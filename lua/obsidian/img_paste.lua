---Compatibility wrapper for the old image-paste module.
---
---Image paste now lives in `obsidian.paste` so it can share the same
---location-aware machinery as general paste. Keep these exports for existing
---`require("obsidian.img_paste")` users and `:Obsidian paste_img`.
local M = {}

M.get_clipboard_img_type = function(opts)
  return require("obsidian.paste").get_clipboard_img_type(opts)
end

M.paste = function(path, img_type, opts)
  return require("obsidian.paste").paste_image(path, img_type, opts)
end

return M
