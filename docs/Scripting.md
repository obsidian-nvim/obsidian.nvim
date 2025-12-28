## `Obsidian` global variable

Get the current state of obsidian, with `Obsidian`, it is useful for making plugin integrations or your own scripts.

```lua
local dir = Obsidian.dir
local workspace = Obsidian.workspace
local opts = Obsidian.opts

local daily_notes_dir = opts.daily_notes.dir
```
