- [Save location](#save-location)
- [Open](#open)
- [Options](#options)

## Save location

Option for attachment location is `opts.attachments.folder`

1. for vault root, set it to `/`.
2. for fixed folder, set it to `/folder-name`.
3. for same folder as current file, set it to `./`
4. for sub folder in current folder, set it to `./folder-name`

## Open

Attachment opening is by default controlled by [`vim.ui.open`](https://neovim.io/doc/user/lua.html#vim.ui.open()), customize it like following:

```lua
vim.ui.open = (function(overridden)
  return function(uri, opt)
    if vim.endswith(uri, ".png") then
      vim.cmd("edit " .. uri) -- early return to just open in neovim
      return
    elseif vim.endswith(uri, ".pdf") then
      opt = { cmd = { "zathura" } } -- override open app
    end
    return overridden(uri, opt)
  end
end)(vim.ui.open)
```


Put any where in you config that loads before you open attachments, a good place could be `opts.callback.enter_note`

## Options

```lua
---@class obsidian.config.AttachmentsOpts
---
---Default folder to save images to, relative to the vault root (/) or current dir (.), see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Images#change-image-save-location
---@field folder? string
---
---Default name for pasted images
---@field img_name_func? fun(): string
---
---Default text to insert for pasted images
---@field img_text_func? fun(path: obsidian.Path): string
---
---Whether to confirm the paste or not. Defaults to true.
---@field confirm_img_paste? boolean
attachments = {
  folder = "attachments",
  img_text_func = require("obsidian.builtin").img_text_func,
  img_name_func = function()
    return string.format("Pasted image %s", os.date "%Y%m%d%H%M%S")
  end,
  confirm_img_paste = true, -- TODO: move to paste module, paste.confirm
}
```
