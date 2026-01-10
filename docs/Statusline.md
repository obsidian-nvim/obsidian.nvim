> [!Warning]
> Deprecated in favor of [[Footer]].
> However, only the configuration options will be deprecated, you can still access the buffer local variable to get access to the note status string.

To see statusline component similar to the obsidian app, you just need to read the global variable `vim.b.obsidian_status` to get a formatted text.

If you are using `lualine.nvim`, use:

```lua
require("lualine").setup {
  sections = {
    lualine_x = {
      "b:obsidian_status",
    },
  },
}
```

> [!Warning]
> the old `vim.g.obsidian`/`g:obsidian` approach no longer works


The status is lazily computed, only updates when you are in an obsidian note, and when the properties change.

You can also turn it off or reformat the string in the statusline module (will be deprecated and the format will be controlled by `footer.format` in the future):

```lua
require("obsidian").setup {
  statusline = {
    enabled = false, -- turn it off
    format = "{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars", -- works like the template system
  },
}
```
