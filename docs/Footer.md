By default, `obsidian.nvim` displays footer similar to the obsidian app.
You can change the footer options as below:

```lua
require("obsidian").setup {
  footer = {
    enabled = false, -- turn it off
    separator = false, -- turn it off
    -- separator = "", -- insert a blank line
    format = "{{status}}", -- default status text
    -- format = "({{backlinks}} backlinks)", -- limit to backlinks
    -- format = "Backlinks:\n{{linked_mentions}}", -- multiline
    hl_group = "@property", -- Use another hl group
    substitutions = {
      -- custom token used as {{my_token}}
      my_token = function(ctx)
        return string.format("%s (%d backlinks)", ctx.note.id, #ctx.backlinks())
      end,
    },
  },
}
```

Built-in substitutions:

- `{{status}}` renders `{{backlinks}} backlinks  {{properties}} properties  {{words}} words  {{chars}} chars`
- `{{words}}`, `{{chars}}`, `{{properties}}`, `{{backlinks}}`
- `{{linked_mentions}}` renders:
  - `Linked Mentions`
  - blank line
  - `<vault_rel_path>: <matched line text>` per backlink
  - if there are no linked mentions, it renders nothing
- `{{unlinked_mentions}}` is currently a placeholder for future functionality

## Options

```lua
---@class obsidian.config.FooterOpts
---
---@field enabled? boolean
---@field format? string
---@field hl_group? string
---@field separator? string|false Set false to disable separator; set an empty string to insert a blank line separator.
---@field substitutions? table<string, string|number|string[]|fun(ctx: obsidian.FooterContext): string|string[]|number|nil>
footer = {
  enabled = true,
  format = "{{status}}",
  hl_group = "Comment",
  separator = string.rep("-", 80),
  substitutions = {},
}
```
