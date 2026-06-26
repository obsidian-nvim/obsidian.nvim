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

At the moment, the cache is used for `:Obsidian quick_switch`. When enabled, quick switch reads note names and aliases from the cache instead of asking the picker to scan the vault each time.

## What Gets Cached

The cache stores note metadata that helps `quick_switch` build picker entries:

- note path
- aliases
- tags
- frontmatter properties
- outgoing links
- tasks
- file modification time and size

The cache is derived data. You can delete it at any time; `obsidian.nvim` will rebuild it on the next startup or file change.

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
{stdpath("cache")}/obsidian.nvim/{sha256(vault_path):sub(1, 16)}.json
```

Each vault gets its own cache file.

## How Updates Work

On startup, `obsidian.nvim` checks the vault for supported Markdown files and updates entries whose modification time or size changed.

While Neovim is running, file watch events update the cache when notes are created, changed, deleted, or renamed.

The cache follows your existing `file.ignore_filters` setting.

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
