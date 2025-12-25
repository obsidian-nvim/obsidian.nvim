## Deprecation of legacy commands

Currently commands are available in two formats, for example:

- `ObsidianExtractNote` (legacy format)
- `Obsidian extract_note`

> [!warning]
> The legacy format of commands will no longer be maintained from version 4.0.0.

You can clean the `Obsidian` namespace by passing the following into the setup function:

```lua
require("obsidian").setup({
   legacy_commands = false,
})
```
