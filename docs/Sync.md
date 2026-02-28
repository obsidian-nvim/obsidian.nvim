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

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `headless_sync.watch` | `boolean` | `false` | Run sync in continuous mode (watches for changes) |
| `headless_sync.conflict_strategy` | `string` | `"merge"` | How to handle conflicts: `"merge"` or `"conflict"` |
| `headless_sync.file_types` | `string[]` | `{"image", "audio", "video", "pdf", "unsupported"}` | File types to sync |
| `headless_sync.configs` | `string[]` | `{"app", "appearance", "appearance-data", "hotkey", "core-plugin", "core-plugin-data", "community-plugin", "community-plugin-data"}` | Config categories to sync |
| `headless_sync.excluded_folders` | `string[]` | `{}` | Folders to exclude from sync |
| `headless_sync.device_name` | `string?` | `nil` | Device name shown in sync version history |
| `headless_sync.config_dir` | `string` | `".obsidian"` | Config directory name |

## Configuration Example

```lua
require("obsidian").setup {
  headless_sync = {
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
local sync = require("obsidian.sync")

-- Check if headless is installed
if sync.check_installed() then
  local h = sync.new()
  
  -- List remote vaults
  local remote = h:list_remote()
  
  -- Check if vault is configured
  if h:is_configured("/path/to/vault") then
    -- Run sync
    h:sync("/path/to/vault", false)
  end
end
```

### Available Methods

- `sync.check_installed()` - Check if obsidian-headless is installed
- `sync.new()` - Create a new Headless instance
- `h:login(email, password)` - Login to Obsidian Sync
- `h:list_remote()` - List remote vaults
- `h:list_local()` - List locally configured vaults
- `h:is_configured(path)` - Check if vault is configured
- `h:setup(vault_name, path)` - Configure a vault for sync
- `h:apply_config(path, opts)` - Apply sync configuration
- `h:sync(path, watch)` - Run sync
- `h:status(path)` - Get sync status
- `h:unlink(path)` - Disconnect vault from sync
- `h:get_config(path)` - Get current sync config
- `h:set_config(path, opts)` - Set sync config
- `h:create_remote(name, opts)` - Create a new remote vault
