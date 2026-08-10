---
title: "Cache"
tags:
  - configuration
  - performance
---

The cache is disabled by default. To use it, enable it in your `obsidian.nvim` config:

```lua
require("obsidian").setup {
  cache = {
    enabled = true,
  },
}
```

The default backend is `json`. It writes a cache file under Neovim's cache directory and reuses it between sessions. You do not need to set `backend = "json"` unless you want to be explicit.

The cache powers `:Obsidian quick_switch`, note-symbol lookup and completion, Obsidian bookmark queries, the built-in query picker, and vault-wide heading completion (`[[##query`). Quick switch reads note names, aliases, attachments, and missing-link targets from the cache. Query execution requires an enabled cache; content predicates use ripgrep against the file set already validated by the cache, while metadata-only predicates do not start ripgrep.

## What Gets Cached

The cache stores typed note and attachment rows with derived facts used by symbol lookup, query evaluation, and picker entries:

- note/file path
- note ID and aliases
- headings (original text, normalized anchor, level, and line)
- tags
- frontmatter properties
- normalized and vault-relative note paths, filenames, extensions, IDs, titles, and aliases
- normalized tags plus their original spelling and locations
- outgoing links
- task state, text, original line, and location
- heading, section, and block ranges
- line count and file kind (`markdown` or `canvas`)
- file modification time and size
- attachment extension and file statistics

Attachment content is not stored in the metadata cache.

Complete note contents and complete line arrays are not cached. When query semantics require content, `obsidian.search.query` obtains complete-line evidence through ripgrep and evaluates the existing query AST in Lua.

The searchable extension set is shared by cache scanning and ripgrep:

- `.md`
- `.markdown`
- `.qmd`
- `.base`
- `.canvas`

The cache is derived data. You can delete it at any time; `obsidian.nvim` will rebuild it on the next startup or file change.

## Volatile indexes

Some derived data is intentionally kept in memory and is never written to the
configured backend. These values are built only when the corresponding feature
is first used:

- vault-wide block candidates
- source-aware tag occurrences and completion counts
- per-buffer parsed documents and inlay-hint responses
- note-name and alias lookup symbols used by link suggestions

Vault indexes react to normalized create, change, delete, and rename events.
Loaded modified buffers overlay their on-disk entries where applicable.
Per-buffer values use the buffer's changed tick and are removed when the buffer
is detached. Workspace and relevant configuration changes invalidate these
values automatically.

The `memory` backend is different: it is an in-memory implementation of the
persistent metadata store and still performs that store's startup scan.
Volatile indexes do not perform work at startup and cannot be replaced with a
custom backend.

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

On startup, `obsidian.nvim` checks the vault for supported note and attachment types, including searchable Markdown-like and canvas files, and updates entries whose modification time (including nanoseconds) or size changed.
Persisted entries are not exposed to queries until this validation finishes.

The JSON backend uses a versioned schema. Incompatible cache data is discarded
and rebuilt from the vault rather than migrated in place.

LSP `textDocument/didSave` notifications refresh saved notes immediately. Plugin-initiated moves, renames, and deletes update the cache directly, while file watch events cover external changes.

The cache follows your existing `file.ignore_filters` setting. Vault
configuration files and Git internals are excluded.

To force a full rescan after external changes or suspected stale data, run:

```vim
:Obsidian rebuild_cache
```

The command reparses every supported note, removes entries for missing files, and flushes the rebuilt cache immediately.

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

- Obsidian query execution requires an enabled cache and the `rg` executable for content predicates.
- Query roots outside the active cached vault are rejected instead of falling back to a filesystem scan.
- Heading and block completion remain query-filtered instead of sending every heading or block to the completion engine.
- Running several Neovim instances on the same vault can cause cache updates to race.

## See also

[[Completion]] · [[Search]] · [[Workspace]]
