local M = {}
local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.util"
local Path = require "obsidian.path"

local save_attachment = require "obsidian.paste.save"
M.get_attachment_type = require "obsidian.paste.get_type"

---@param path string image_path The absolute path to the image file.
---@return string?
local _paste = function(path, mime_type)
  if util.contains_invalid_characters(path) then
    log.warn "Links will not work with file names containing any of these characters in Obsidian: # ^ [ ] |"
  end

  ---@diagnostic disable-next-line: cast-local-type
  path = Path.new(path)

  -- If there is no suffix provided, append it
  if not path.suffix then
    ---@diagnostic disable-next-line: cast-local-type
    path = path:with_suffix("." .. mime_type)

  -- If user appends their own suffix, check if it is valid based on img_type
  elseif not (path.suffix == "." .. mime_type or (mime_type == "jpeg" and path.suffix == ".jpg")) then
    local expected_suffix = (mime_type == "jpeg") and ".jpeg' or '.jpg" or "." .. mime_type
    log.err("invalid suffix for image name '%s', must be '%s'", path.suffix, expected_suffix)
    return
  end

  if Obsidian.opts.attachments.confirm_img_paste then -- TODO: confirm_paste
    -- Get confirmation from user.
    if not api.confirm("Saving image to '" .. tostring(path) .. "'. Do you want to continue?") then
      return log.warn "Paste aborted"
    end
  end

  -- Ensure parent directory exists.
  assert(path:parent()):mkdir { exist_ok = true, parents = true }

  -- Paste image.
  local result = save_attachment(tostring(path), mime_type)
  if result == false then
    log.err "Failed to save image"
    return
  end

  local img_text = Obsidian.opts.attachments.img_text_func(path) -- TODO: deprecate img_text_func, just follow link.style
  return img_text
end

---@return string[]?
M.get = function(fname, mime_type)
  ---@type string|?
  local default_name = Obsidian.opts.attachments.img_name_func() -- TODO: attachments.name_func()

  local should_confirm = Obsidian.opts.attachments.confirm_img_paste -- TODO: attachments.confirm

  -- Get filename to save to.
  if fname == nil or fname == "" then
    if default_name and not should_confirm then
      fname = default_name
    else
      local input = api.input("Enter file name: ", { default = default_name, completion = "file" })
      if not input then
        return log.warn "Paste aborted"
      end
      fname = input
    end
  end

  ---@type string
  fname = vim.trim(fname)

  local path = api.resolve_image_path(fname)

  return { _paste(path, mime_type) }
end

return M
