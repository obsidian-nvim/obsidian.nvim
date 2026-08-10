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

The cache powers `:Obsidian quick_switch`, note-symbol lookup, Obsidian bookmark queries, and the built-in query picker. Query execution is intentionally unavailable when the cache is disabled. Content predicates use ripgrep against the file set already validated by the cache; metadata-only predicates do not start ripgrep.

## What Gets Cached

The cache stores derived facts used by symbol lookup and query evaluation:

- normalized and vault-relative note paths, filenames, extensions, IDs, titles, and aliases
- lossless frontmatter values, including reserved and explicitly empty values
- normalized tags plus their original spelling and locations
- outgoing links
- task state, text, original line, and location
- heading, section, and block ranges
- line count and file kind (`markdown` or `canvas`)
- file modification time and size

Complete note contents and complete line arrays are not cached. When query semantics require content, `obsidian.search.query` obtains complete-line evidence through ripgrep and evaluates the existing query AST in Lua.

The searchable extension set is shared by cache scanning and ripgrep:

- `.md`
- `.markdown`
- `.qmd`
- `.base`
- `.canvas`

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

On startup, `obsidian.nvim` checks the vault for supported searchable files and updates entries whose modification time (including nanoseconds) or size changed.
Persisted entries are not exposed to queries until this validation finishes.

LSP `textDocument/didSave` notifications refresh saved notes immediately. Plugin-initiated moves, renames, and deletes update the cache directly, while file watch events cover external changes.

The cache follows your existing `file.ignore_filters` setting.

Every cache mutation also updates a shared in-memory symbol index and increments a generation counter. Long-running queries use a stable snapshot and will retry or reject results if the generation changes before publication.

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

- Obsidian query execution requires both an enabled cache and the `rg` executable for content predicates.
- Query roots outside the active cached vault are rejected instead of falling back to a filesystem scan.
- Running several Neovim instances on the same vault can cause cache updates to race.
