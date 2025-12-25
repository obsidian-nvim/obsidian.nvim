> [!Warning]
> Deprecated in favor of
> [`Footer`](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Footer).

To see statusline component similar to the obsidian app, you just need to read the global variable `vim.g.obsidian` to get a formatted text.

If you are using `lualine.nvim`, use:

```lua
require("lualine").setup({
   sections = {
      lualine_x = {
         "g:obsidian",
      },
   },
})
```

The status is lazily computed, only updates when you are in an obsidian note, and when the properties change.

You can also turn it off or reformat the string in the statusline module:

```lua
require("obsidian").setup({
   statusline = {
      enabled = false, -- turn it off
      format = "{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars", -- works like the template system
   },
})
```
