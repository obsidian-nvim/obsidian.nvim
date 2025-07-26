local Path = require "obsidian.path"
local api = require "obsidian.api"
local log = require "obsidian.log"
local img = require "obsidian.img_paste"

---@param data CommandArgs
return function(_, data)
  if not img.clipboard_is_img() then
    return log.err "There is no image data in the clipboard"
  end

  local img_folder = Path.new(Obsidian.opts.attachments.img_folder)
  if not img_folder:is_absolute() then
    img_folder = Obsidian.dir / Obsidian.opts.attachments.img_folder
  end

  ---@type string|?
  local default_name = Obsidian.opts.attachments.img_name_func()

  local should_confirm = Obsidian.opts.attachments.confirm_img_paste

  ---@type string?
  local fname = vim.trim(data.args)

  -- Get filename to save to.
  if fname == nil or fname == "" then
    if default_name and not should_confirm then
      fname = default_name
    else
      fname = api.input("Enter file name: ", {
        default = default_name,
        completion = "file",
      })
      if fname == "" then
        fname = default_name
      elseif not fname then
        return log.warn "Paste aborted"
      end
    end
  end

  local path = api.resolve_image_path(fname)

  img.paste(path)
end
