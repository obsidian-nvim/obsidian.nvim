- [Save location](#save-location)
- [Add attachment](#add-attachment)
- [Open](#open)
- [Options](#options)

## Save location

Option for attachment location is `opts.attachments.folder`

1. for vault root, set it to `/`.
2. for fixed folder, set it to `/folder-name`.
3. for same folder as current file, set it to `./`
4. for sub folder in current folder, set it to `./folder-name`

## Add attachment

Use `require"obsidian.actions".add_attachment(source)` or invoke it via code action.

- If `source` is a local file (or `file://` URI), the file is copied.
- If `source` is a local directory, a file picker is opened, and selected file is copied.
- If `source` is a `http(s)` URL, the file is downloaded with `curl`.
- The destination path is always resolved by `api.resolve_attachment_path()` and controlled by [Save location](#save-location)

When called without an argument, obsidian.nvim uses `opts.attachments.resolve`.

Pick with a terminal file manager (yazi in a centered float):

```lua
attachments = {
  resolve = function(opts)
    local tmp = vim.fn.tempname()
    local buf = vim.api.nvim_create_buf(false, true)
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
    })
    vim.fn.jobstart({ "yazi", "--chooser-file=" .. tmp }, {
      term = true,
      on_exit = function()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
        if vim.uv.fs_stat(tmp) then
          local lines = vim.fn.readfile(tmp)
          if lines[1] then
            require("obsidian.attachment").add(lines[1], opts)
          end
        end
      end,
    })
    vim.cmd "startinsert"
  end,
}
```

## Open

Attachment opening is by default controlled by `:h vim.ui.open`, customize it like following:

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
---
---Controls how actions.add_attachment resolves attachments from outside the vault.
---@field resolve? fun(opts: { insert: boolean|? })|?
attachments = {
  folder = "attachments",
  img_text_func = require("obsidian.builtin").img_text_func,
  img_name_func = function()
    return string.format("Pasted image %s", os.date "%Y%m%d%H%M%S")
  end,
  confirm_img_paste = true, -- TODO: move to paste module, paste.confirm
  resolve = require("obsidian.builtin").resolve_attachment_func,
}
```
