## Options

```lua
---@class obsidian.config.OpenOpts
---
---Opens the file with current line number
---@field use_advanced_uri? boolean
---
---Function to do the opening, default to vim.ui.open
---@field func? fun(uri: string)
---
---URI scheme whitelist, new values are appended to this list, and URIs with schemes in this list, will not be prompted to confirm opening
```
