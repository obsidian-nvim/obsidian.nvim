# What is Cache?

Cache in `obsidian.nvim` is a JSON file under Neovim's `stdpath("cache")`, which stores information for each note in the user's workspace.

The information is stored as a map keyed by absolute note path. Each value stores only data that is expensive to reparse or needed to detect changes:

- Aliases.
- Lowercased tags.
- Frontmatter properties.
- Outgoing links.
- Tasks.
- Last modification time and file size.

Path-derived fields like relative path, basename, extension, and folder are computed from the map key when needed instead of persisted. Empty collections are omitted.

# How Works

TLDR:

- The cache file is used by pickers.
- The cache file is updated by event handlers from libuv library and on the startup, comparing the last modification time of the notes.

The following sections describe the functionality in more details.

## Updates When Neovim is not Active.

Notes can be updated by programs like like git, syncthing or any cloud storage providers when neovim was not active. For this case, during the startup all notes are checked for last modification time. If the time is different from the time in the cache file, then the file is checked for changes.

## How Pickers use the Cache File

The functionality of the `quick_switch` command was changed in the following way:
the `find_files` uses the cache file as the source, instead of using `rg`.
Aliases, which are placed in the cache file are concatenated after the relative file path with `|` sign.
Example of an entry: `Base/MongoDB Drop Field.md|MongoDB Unset Field|MongoDB Remove Field`

# How to Use

## Location

The cache is stored outside the vault at:

```text
{stdpath("cache")}/obsidian.nvim/{sha256(vault_path):sub(1, 16)}.json
```

It is derived state and can be deleted at any time. The next startup or file change will rebuild it.

## Enable the Module

By default, the cache module is disabled.

If you use `lazy.nvim`, in your configuration file add the following option:

```lua
cache = {
  enabled = true,
},
```

Read the [configuration](https://github.com/obsidian-nvim/obsidian.nvim#%EF%B8%8F-configuration) section for more information.

## Custom Backends

Built-in backends are `json` and `memory`. Custom backends can be registered by name before setup:

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

A store implements `get(key)`, `all()`, `put(key, row)`, and `delete(key)`. `flush()` and `close()` are optional lifecycle hooks.

The cache uses `file.ignore_filters` for ignored files and directories.

# Limitations

- Several instances of neovim can conflict with each other, because each creates it's own file watch handles.
