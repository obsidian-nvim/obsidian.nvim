- [Installation](#installation)
- [Commands](#commands)
- [Configuration Example](#configuration-example)
- [Options](#options)

The Sync module integrates with [Obsidian Headless](https://help.obsidian.md/sync/headless) to sync vaults from the CLI without requiring the desktop app. This is useful for headless environments, CI pipelines, or CLI-only workflows.

## Installation

In the plugin installation folder:

```bash
npm install obsidian-headless
```

or just install globally

```bash
npm install obsidian-headless -g
```

## Commands

### `:Obsidian sync`

Sync the current workspace vault. On first run, it will:

1. Check if logged in (prompt for credentials if not)
2. Check if vault is configured (prompt for vault name if not)
3. Apply sync configuration from plugin settings
4. Run the sync

When switching workspaces, any running continuous sync process for the previous workspace is stopped before starting sync for the new workspace.

## Configuration Example

```lua
require("obsidian").setup {
  sync = {
    conflict_strategy = "merge",
    file_types = { "image", "audio", "video", "pdf", "unsupported" },
    configs = {
      "app",
      "appearance",
      "appearance-data",
      "hotkey",
      "core-plugin",
      "core-plugin-data",
      "community-plugin",
      "community-plugin-data",
    },
    excluded_folders = {},
    device_name = nil,
    config_dir = ".obsidian",
  },
}
```

### Available Methods (`require("obsidian.sync")`)

- `sync.start(workspace?)` - Start continuous sync for a workspace (defaults to current workspace)
- `sync.stop(workspace?)` - Stop continuous sync for a workspace (defaults to current workspace)
- `sync.menu(subcmd?)` - Open the sync action menu or run a specific subcommand (`start`, `pause`, `log`, `wizard`)
- `sync.is_configured(workspace)` - Check if a workspace is configured for sync
- `sync.wizard()` - Run the interactive setup wizard

> [!Note]
> lower-level CLI helpers live in `require("obsidian.sync.client")` and are not the primary public API surface.

## Options

```lua
---https://help.obsidian.md/sync/settings
---@class obsidian.config.SyncOpts
---
---@field enabled? boolean
---@field conflict_strategy? "merge"|"conflict"
---@field file_types? string[]
---@field configs? string[]
---@field excluded_folders? string[]
---@field device_name? string
---@field config_dir? string
sync = {
  enabled = false,
  conflict_strategy = "merge",
  file_types = { "image", "audio", "video", "pdf", "unsupported" },
  configs = {
    "app",
    "appearance",
    "appearance-data",
    "hotkey",
    "core-plugin",
    "core-plugin-data",
    "community-plugin",
    "community-plugin-data",
  },
  excluded_folders = {},
  device_name = nil,
  config_dir = ".obsidian",
}
```
