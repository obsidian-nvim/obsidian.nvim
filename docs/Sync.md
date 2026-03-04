# Sync

[[#Options]]

The Sync module integrates with [Obsidian Headless](https://help.obsidian.md/sync/headless) to sync vaults from the CLI without requiring the desktop app. This is useful for headless environments, CI pipelines, or CLI-only workflows.

## Installation

```bash
cd ~/.local/share/nvim/lazy/obsidian.nvim
npm install obsidian-headless
```

## Commands

### `:Obsidian sync`

Sync the current workspace vault. On first run, it will:

1. Check if logged in (prompt for credentials if not)
2. Check if vault is configured (prompt for vault name if not)
3. Apply sync configuration from plugin settings
4. Run the sync

## Options

| Option                   | Type       | Default                                                                                                                              | Description                                        |
| ------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- |
| `sync.watch`             | `boolean`  | `false`                                                                                                                              | Run sync in continuous mode (watches for changes)  |
| `sync.conflict_strategy` | `string`   | `"merge"`                                                                                                                            | How to handle conflicts: `"merge"` or `"conflict"` |
| `sync.file_types`        | `string[]` | `{"image", "audio", "video", "pdf", "unsupported"}`                                                                                  | File types to sync                                 |
| `sync.configs`           | `string[]` | `{"app", "appearance", "appearance-data", "hotkey", "core-plugin", "core-plugin-data", "community-plugin", "community-plugin-data"}` | Config categories to sync                          |
| `sync.excluded_folders`  | `string[]` | `{}`                                                                                                                                 | Folders to exclude from sync                       |
| `sync.device_name`       | `string?`  | `nil`                                                                                                                                | Device name shown in sync version history          |
| `sync.config_dir`        | `string`   | `".obsidian"`                                                                                                                        | Config directory name                              |

## Configuration Example

```lua
require("obsidian").setup {
  sync = {
    watch = false,
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

## Lua API

The sync module can also be used programmatically:

```lua
local sync = require "obsidian.sync"

-- Check if headless is installed
if sync.check_installed() then
  local h = sync.new()

  -- List remote vaults
  local remote = h:list_remote()

  -- Check if vault is configured
  if h:is_configured "/path/to/vault" then
    -- Run sync
    h:sync("/path/to/vault", false)
  end
end
```

### Available Methods

- `sync.check_installed()` - Check if obsidian-headless is installed
- `sync.new()` - Create a new Headless instance
- `sync.login(email, password)` - Login to Obsidian Sync
- `sync.list_remote()` - List remote vaults
- `sync.list_local()` - List locally configured vaults
- `sync.is_configured(path)` - Check if vault is configured
- `sync.setup(vault_name, path)` - Configure a vault for sync
- `sync.apply_config(path, opts)` - Apply sync configuration
- `sync.sync(path, watch)` - Run sync
- `sync.status(path)` - Get sync status
- `sync.unlink(path)` - Disconnect vault from sync
- `sync.get_config(path)` - Get current sync config
- `sync.set_config(path, opts)` - Set sync config
- `sync.create_remote(name, opts)` - Create a new remote vault
