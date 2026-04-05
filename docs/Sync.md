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

### Available Methods

- `sync.login(email, password)` - Login to Obsidian Sync
- `sync.list_remote()` - List remote vaults
- `sync.list_local()` - List locally configured vaults
- `sync.is_configured(workspace)` - Check if vault is configured
- `sync.setup(vault_name, path)` - Configure a vault for sync
- `sync.apply_config(path, opts)` - Apply sync configuration
- `sync.status(path)` - Get sync status
- `sync.unlink(path)` - Disconnect vault from sync
- `sync.get_config(path)` - Get current sync config
- `sync.set_config(path, opts)` - Set sync config
- `sync.create_remote(name, opts)` - Create a new remote vault

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
