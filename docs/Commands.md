## Deprecation of legacy commands

Currently commands are available in two formats, for example:

- `ObsidianExtractNote` (legacy format)
- `Obsidian extract_note`

> [!warning]
> The legacy format of commands will no longer be maintained from version 4.0.0.

You can clean the `Obsidian` namespace by passing the following into the setup function:

```lua
require("obsidian").setup {
  legacy_commands = false,
}
```

## Completion for sub-commands

For real completion as you type, add following snippet to your config, this will not play well with custom cmdline completion implementations like blink.cmp or nvim-cmp, it is recommended you use [mini.cmdline](https://nvim-mini.org/mini.nvim/readmes/mini-cmdline.html), or explore how the plugins above can be avoided from being triggered in this context, and share the solution, so that the following snippet can become the default.

```lua
vim.api.nvim_create_autocmd("CmdlineChanged", {
  callback = function()
    local cmdline = vim.fn.getcmdline()
    if vim.fn.getcmdtype() ~= ":" then
      return
    end
    if not cmdline:match "^Obsidian[A-Za-z0-9]*$" then
      return
    end
    vim.fn.wildtrigger()
  end,
})
```
