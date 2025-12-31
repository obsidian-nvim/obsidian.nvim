## Options

```lua
---@class obsidian.config.OpenOpts
---@field use_advanced_uri boolean opens the file with current line number
---@field func fun(uri: string) default to vim.ui.open
```

## Open func

`opts.open.func` defaults to [`vim.ui.open`](https://neovim.io/doc/user/lua.html#vim.ui.open())

It has two jobs:

1. Open obsidian app for `:Obsidian open`
2. Open attachments

### Example

```lua
require("obsidian").setup {
  open = {
    func = function(uri)
      if vim.endswith(uri, ".png") then
        vim.cmd("edit " .. uri)
      end
    end,
  },
}
```
