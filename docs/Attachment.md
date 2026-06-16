- [Save location](#save-location)
- [Add attachment](#add-attachment)
- [Paste from clipboard path](#paste-from-clipboard-path)
- [Open](#open)
- [Options](#options)

## Save location

Option for attachment location is `opts.attachments.folder`

1. for vault root, set it to `/`.
2. for fixed folder, set it to `/folder-name`.
3. for same folder as current file, set it to `./`
4. for sub folder in current folder, set it to `./folder-name`

## Add attachment

There are two attachment entry points:

- `require("obsidian.attachment").add(source, opts)` is the lower-level API. It copies or downloads `source`, then optionally inserts a link.
- `require("obsidian.actions").add_attachment(source, opts)` is the interactive action wrapper, and is what the code action invokes. It prompts when `source` is missing, opens a picker when `source` is a directory, then delegates to `attachment.add()`.

For `attachment.add(source, opts)`:

- If `source` is a local file (or `file://` URI), the file is copied.
- If `source` is a `http(s)` URL, the file is downloaded with `curl`.
- The destination path is always resolved by `api.resolve_attachment_path()` and controlled by [Save location](#save-location).
- Set `opts.new_name` to copy/download the attachment with a different destination basename.

For `actions.add_attachment(source, opts)`:

- If `source` is a local directory, a file picker is opened, and the selected file is copied.
- If `source` is missing or empty, obsidian.nvim prompts for a URL or file path.
- The target `bufnr` must be an obsidian buffer.

Both functions accept the same `opts` table:

```lua
---@class obsidian.AttachmentAddOpts
---@field insert? boolean Insert the generated attachment link after adding. Defaults to true.
---@field bufnr? integer Buffer used for relative attachment resolution and link insertion. Defaults to current buffer.
---@field new_name? string Destination attachment basename. Path separators are rejected.
```

## Paste from clipboard path

If your clipboard contains a file path, you can add it directly with `attachment.add()`.
The example below checks that the clipboard resolves to an existing path first and reports the aborted branch through `obsidian.log`:

```lua
local log = require "obsidian.log"

local paste_from_path = function()
  local path = vim.trim(vim.fn.getreg "+")
  if path == "" then
    return log.warn "Clipboard is empty"
  end

  local stat_path = vim.startswith(path, "file://") and vim.uri_to_fname(path) or path
  if not vim.uv.fs_stat(stat_path) then
    return log.warn("Clipboard does not contain a valid path: %s", path)
  end

  vim.schedule(function()
    require("obsidian.attachment").add(path, { insert = true })
  end)
end
```

To customize how attachment is resolved, use `opts.resolvers.attachment`.
For example, pick with a terminal file manager:

```lua
require("obsidian").setup {
  resolvers = {
    attachment = function(ctx, done)
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
              done { path = lines[1] }
              return
            end
          end
          done(nil)
        end,
      })
      vim.cmd "startinsert"
    end,
  },
}
```

See [[Resolvers]] for the full resolver contract.

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
attachments = {
  folder = "attachments",
  img_text_func = require("obsidian.builtin").img_text_func,
  img_name_func = function()
    return string.format("Pasted image %s", os.date "%Y%m%d%H%M%S")
  end,
  confirm_img_paste = true, -- TODO: move to paste module, paste.confirm
}
```
