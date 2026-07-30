# Cache

The cache is disabled by default. To use it, enable it in your `obsidian.nvim` config:

```lua
require("obsidian").setup {
  cache = {
    enabled = true,
  },
}
```

The default backend is `json`. It writes a cache file under Neovim's cache directory and reuses it between sessions. You do not need to set `backend = "json"` unless you want to be explicit.

At the moment, the cache is used for `:Obsidian quick_switch`. When enabled, quick switch reads note names, aliases, attachments, and missing-link targets from the cache instead of asking the picker to scan the vault each time.

## What Gets Cached

The cache stores typed note and attachment entries that help `quick_switch` build picker entries:

- file path
- aliases
- tags
- frontmatter properties
- outgoing links
- tasks
- file modification time and size
- attachment extension and file statistics

Attachment content is not stored in the metadata cache.

The cache is derived data. You can delete it at any time; `obsidian.nvim` will rebuild it on the next startup or file change.

## Quick Switch Options

By default quick switch only shows existing notes, not attachments. With the cache enabled you can opt into missing links and attachments:

```lua
require("obsidian").setup {
  quick_switch = {
    show_existing_only = false,
    show_attachments = true,
  },
}
```

## Enable the Cache

You can also set the backend explicitly:

```lua
require("obsidian").setup {
  cache = {
    enabled = true,
    backend = "memory",
  },
}
```

## Cache Location

With the default `json` backend, the cache file is stored at:

```text
{stdpath("cache")}/obsidian.nvim/{sha256(vault_path):sub(1, 16)}/index.json
```

Each vault gets its own cache directory. This leaves room for optional derived
artifacts without putting large content in `index.json`.

## How Updates Work

On startup, `obsidian.nvim` checks the vault for supported Markdown files and attachment types and updates entries whose modification time (including nanoseconds) or size changed.
Persisted entries are not exposed to queries until this validation finishes.

The JSON backend uses a versioned schema. Incompatible cache data is discarded
and rebuilt from the vault rather than migrated in place.

LSP `textDocument/didSave` notifications refresh saved notes immediately. Plugin-initiated moves, renames, and deletes update the cache directly, while file watch events cover external changes.

The cache follows your existing `file.ignore_filters` setting. Vault
configuration files and Git internals are excluded.

## Backends

Built-in backends:

- `json`: default, persists between sessions
- `memory`: in-memory only, useful for tests or temporary sessions

Custom backends can be registered before setup:

```lua
require("obsidian.cache").register("my-store", {
  open = function(opts)
    return store
  end,
})

cache = {
  enabled = true,
  backend = "my-store",
}
```

A store implements `get(key)`, `all()`, `put(key, row)`, and `delete(key)`. `flush()` and `close()` are optional.

## Limitations

- The cache currently powers `:Obsidian quick_switch` only.
- Running several Neovim instances on the same vault can cause cache updates to race.
