- [Commands](#commands)
- [Sync Settings](#sync-settings)
- [Options](#options)

The Sync module integrates with [Obsidian Headless](https://help.obsidian.md/sync/headless) to sync vaults without requiring the desktop app.

You need a subscription for [Obsidian Sync](https://obsidian.md/help/sync) and follow its initial setup guides, and then explicitly enable this module in your setup:

```lua
require("obisidian").setup {
  sync = {
    enabled = true,
  },
}
```

## Commands

### `:Obsidian sync`

Sync the current workspace vault. On first run, it will:

1. Check if you have a working `obsidian-headless` CLI, if not it will prompt you go install a local copy managed by this plugin, or you can manually install a global CLI with
   `npm install obsidian-headless -g`
2. Check if logged in (prompt for credentials if not)
3. Check if any vault is configured (prompt to create at least one connection to remote)
4. Apply sync configuration from plugin settings
5. Run the sync

When switching workspaces, any running continuous sync process for the previous workspace is stopped before starting sync for the new workspace.

### `:Obsidian sync [SUBCMD]`

Once you have configured a working setup, `:Obsidian sync` alone will work as a menu like top-level `:Obsidian`, you can `<CR>` for the select interface or `<Tab>` it for autocompletion.

Available subcommands:

- `:Obsidian sync start`: start sync for current workspace
- `:Obsidian sync pause`: pause sync for current workspace
- `:Obsidian sync setup`: setup wizard
- `:Obsidian sync disconnect`: disconnect existing connections
- `:Obsidian sync log`: open log for current session

## Sync Settings

These settings map directly to `ob sync-config` options from the [Obsidian Headless CLI](https://help.obsidian.md/sync/headless). They are applied automatically before each sync run.

| Option              | Type                                            | Default                                               | Description                                                                                                                                                                                                       |
| ------------------- | ----------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mode`              | `"bidirectional"\|"pull-only"\|"mirror-remote"` | `nil` (bidirectional)                                 | Sync direction. `pull-only` only downloads and ignores local changes. `mirror-remote` only downloads and reverts local changes.                                                                                   |
| `conflict_strategy` | `"merge"\|"conflict"`                           | `"merge"`                                             | How to handle conflicts. `"conflict"` is not currently supported by the headless client.                                                                                                                          |
| `file_types`        | `string[]`                                      | `{ "image", "audio", "video", "pdf", "unsupported" }` | Attachment types to sync. Use an empty table `{}` to disable attachment syncing.                                                                                                                                  |
| `configs`           | `string[]\|nil`                                 | `nil`                                                 | Obsidian app config categories to sync (e.g. `"app"`, `"appearance"`, `"hotkey"`, `"core-plugin"`, `"community-plugin"`, etc). Only relevant if you share a vault with the desktop app. `nil` skips this setting. |
| `excluded_folders`  | `string[]`                                      | `{}`                                                  | Folders to exclude from syncing.                                                                                                                                                                                  |
| `device_name`       | `string\|nil`                                   | `nil`                                                 | Device name shown in sync version history.                                                                                                                                                                        |
| `config_dir`        | `string`                                        | `".obsidian"`                                         | Config directory name.                                                                                                                                                                                            |

### Available API (`require("obsidian.sync")`)

- `sync.start(workspace?)` - Start continuous sync for a workspace (defaults to current workspace)
- `sync.pause(workspace?)` - Stop continuous sync for a workspace (defaults to current workspace)
- `sync.menu(subcmd?)` - Open the sync action menu or run a specific subcommand (`start`, `pause`, `log`, `setup`, `disconnect`)
- `sync.is_configured(workspace)` - Check if a workspace is configured for sync
- `sync.setup()` - Run the interactive setup wizard
- `sync.disconnect()` - Interactively unlink configured local vaults from remote

> [!Note]
> lower-level CLI helpers live in `require("obsidian.sync.client")` and are not the primary public API surface.

## Options

```lua
---https://help.obsidian.md/sync/settings
---@class obsidian.config.SyncOpts
---
---@field enabled? boolean
---
---Sync mode: bidirectional (default), pull-only (only download, ignore local changes), or mirror-remote (only download, revert local changes)
---@field mode? "bidirectional"|"pull-only"|"mirror-remote"
---
---Conflict strategy when a conflict is detected, NOTE: conflict mode will generate conflict files in your repo, more support will be in later releases, for now prefer merge
---@field conflict_strategy? "merge"|"conflict"
---
---Attachment types to sync: image, audio, video, pdf, unsupported, empty table to disable attachment syncing
---@field file_types? obsidian.sync.FileType[]
---
---Config categories to sync, empty table to disable config syncing, this is config for obsidian app, and is just here for completeness
---@field configs? obsidian.sync.ConfigCategory[]
---
---Config directory name, this is for obsidian app
---@field config_dir? string
---
---Folders to exclude
---@field excluded_folders? string[]
---
---Device name to identify this client in the sync version history
---@field device_name? string
sync = {
  enabled = false,
  mode = nil,
  conflict_strategy = "merge",
  file_types = { "image", "audio", "video", "pdf", "unsupported" },
  configs = nil,
  excluded_folders = {},
  device_name = nil,
  config_dir = ".obsidian",
}
```
