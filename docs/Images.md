## Inline Image viewing

The only image viewing backend that is well tested and supported is [snacks.image](https://github.com/folke/snacks.nvim/blob/main/docs/image.md), and for extra info there's work being done that will give neovim an native [API rendering images](https://github.com/neovim/neovim/pull/31399), so eventually we will just move to that.

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

The default `opts.image_text_func` is trying to be 100% obsidian compatible, and changes with the `opts.preferred_link_style`.

See the implementation in `builtins.lua`.

You can override the default behavior, for example to always use markdown use the base name as the markdown display text, like:

```lua
require("obsidian").setup {
  attachments = {
    img_text_func = function(path)
      local name = vim.fs.basename(tostring(path))
      local encoded_name = require("obsidian.util").urlencode(name)
      return string.format("![%s](%s)", name, encoded_name)
    end,
  },
}
```

The general principle to keep in mind is you want to use the encoded base name for compatibility for snacks.nvim and obsidian app.
