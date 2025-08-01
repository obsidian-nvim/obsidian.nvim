local api = require "obsidian.api"
local log = require "obsidian.log"
local img = require "obsidian.img_paste"

---@param data CommandArgs
return function(_, data)
  if not img.clipboard_is_img() then
    return log.err "There is no image data in the clipboard"
  end

  ---@type string|?
  local default_name = Obsidian.opts.attachments.img_name_func()

  local should_confirm = Obsidian.opts.attachments.confirm_img_paste

  ---@type string
  local fname = vim.trim(data.args)

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

  local path = api.resolve_image_path(fname)

  img.paste(path)
end
