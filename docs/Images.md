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

Native inline rendering is experimental and opt-in. It renders local PNG embeds below their source line using Neovim's experimental `vim.ui.img` buffer placement. Enable it independently from picker previews:

```lua
require("obsidian").setup {
  img = {
    enabled = true,
    embeds = { enabled = true },
  },
}
```

Wiki embeds support Obsidian pixel-size labels such as `![[image.png|300]]` (width, aspect ratio preserved) and `![[image.png|300x200]]` (width and height bounds, aspect ratio preserved). Inline images are currently limited to 80 cells wide, 30 cells high, and the available text width; these draft limits are local, not configurable. Markdown image embeds are also shown, but Markdown alt text is not treated as a size. `require("obsidian.actions").increment()` and `.decrement()` adjust the wiki image under the cursor by one rendered terminal row per action, scaling its width proportionally. Because cell sizes are discrete, the pixel-width change varies with the image and terminal. They update only dimensions already written in the link: `|WIDTH` remains width-only, and `|WIDTHxHEIGHT` retains both dimensions and its ratio. If there is no size label, they resize only the displayed image without editing the note; this temporary size lasts until the buffer is unloaded. They stop at the inline image limits; elsewhere they do nothing. Non-numeric wiki aliases are not changed. Only local PNG files are rendered; remote URLs, non-PNG formats, ambiguous/missing references and unsupported terminals remain ordinary text. Image graphics are added as virtual lines below the embed, starting at the buffer's text column after the number/sign/fold gutter, so source text is never concealed or modified. The image width is limited to the visible text area. Inline display requires a Neovim build with **buffer-relative** `vim.ui.img` support; older builds with `vim.ui.img` but without buffer placement will not display inline images rather than drawing over note text.

Neovim's [#39496](https://github.com/neovim/neovim/pull/39496) code already converts PNG pixels to cell dimensions *when dimensions are omitted*, but does not fit an image to the note's text width, inline height limit, or `|SIZE` bounds. We supply both cell dimensions after aspect-preserving fitting. We currently measure the tty cell size ourselves (falling back to 9×18): the PR's CSI 16t lookup has [a reported issue](https://github.com/neovim/neovim/issues/39496#issuecomment-6018569982) that its author says needs a Neovim C fix. This local measurement and fit should be revisited when upstream sizing is reliable and exposes bounded fitting.

To build the pinned Neovim [#39496](https://github.com/neovim/neovim/pull/39496) branch from this checkout and run it with your usual config:

```sh
nix build "path:$PWD" -o result-nvim
./result-nvim/bin/nvim
```

The old local-image fixture is still available separately with `nix build "path:$PWD#instagram-inline-embed-test" -o result-fixture`. Copy `result-fixture/Instagram.md` and `result-fixture/instagram.png` into a writable vault to try it. A terminal supporting Kitty graphics is required for visual output.

The only other inline image viewing backend that is well tested and supported is [snacks.image](https://github.com/folke/snacks.nvim/blob/main/docs/image.md).

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
