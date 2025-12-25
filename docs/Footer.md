By default, `obsidian.nvim` displays footer similar to the obsidian app.
You can change the footer options as below:

```lua
require("obsidian").setup({
   footer = {
      enabled = false, -- turn it off
      separator = false, -- turn it off
      -- separator = "", -- insert a blank line
      format = "{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars", -- works like the template system
      -- format = "({{backlinks}} backlinks)", -- limit to backlinks
      hl_group = "@property", -- Use another hl group
   },
})
```

## Options

```lua
---@class obsidian.config.FooterOpts
---
---@field enabled? boolean
---@field format? string
---@field hl_group? string
---@field separator? string|false Set false to disable separator; set an empty string to insert a blank line separator.
```
