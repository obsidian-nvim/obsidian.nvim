## Native picker previews (experimental)

Obsidian.nvim can show local PNG files in the built-in picker preview pane through Neovim's experimental `vim.ui.img` API. This is opt-in and currently supports only the native picker and PNG files:

```lua
require("obsidian").setup {
  img = {
    enabled = true,
    picker = {
      enabled = true,
      max_width = 60,
      max_height = 20,
    },
  },
}
```

A Neovim build with `vim.ui.img` and a terminal supporting the Kitty graphics protocol are required. There is no stable public terminal capability probe yet, so an unavailable or failed backend falls back to image filename/type/size text. After successful placement, that fallback text is hidden behind the graphical preview. Image files are read asynchronously, are limited to 10 MiB by default (`img.max_file_size`), and are never fetched from the network. Other picker backends retain their text-only previews.

Image pixels and terminal cells have different shapes. Fitting measures terminal pixel and cell dimensions (as Snacks does) to calculate the cell aspect ratio. If the terminal does not report pixel dimensions, it falls back to a 9×18 cell estimate.

The display service is also available experimentally as `require("obsidian.img")`. `owner(opts)` creates a scoped owner with idempotent `owner:close()`, `owner:show(...)` and `owner:update(...)`; `show(source, placement, opts)` is a convenience wrapper. Callers must pass an absolute local PNG path or PNG bytes. Owners delete only image IDs they created.

## Inline Image viewing

Inline note rendering remains separate from native picker previews. The only inline image viewing backend that is well tested and supported is [snacks.image](https://github.com/folke/snacks.nvim/blob/main/docs/image.md).

For proper image path resolving, add the following snippet to your snacks config, it will only effect markdown files in your vault:

(_API could could change in the future_)

```lua
require("snacks").setup {
  image = {
    resolve = function(path, src)
      local api = require "obsidian.api"
      if api.path_is_note(path) then
        return api.resolve_attachment_path(src)
      end
    end,
  },
}
```

Then you are good to go.

## Change image insert text

The default `opts.attachments.img_text_func` is trying to be 100% Obsidian compatible, and changes with `opts.link.style`.

See the implementation in `builtin.lua`.

You can override the default behavior, for example to always use markdown use the base name as the markdown display text, like:

```lua
require("obsidian").setup {
  attachments = {
    img_text_func = function(path)
      local name = vim.fs.basename(tostring(path))
      local encoded_name = require("obsidian.uri").encode(name)
      return string.format("![%s](%s)", name, encoded_name)
    end,
  },
}
```

The general principle to keep in mind is you want to use the encoded base name for compatibility for snacks.nvim and obsidian app.
