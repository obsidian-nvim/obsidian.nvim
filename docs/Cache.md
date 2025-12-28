> [!Warning]
> The cache is under development, so it can have bugs and the functionality might be changed in the future.

# What is Cache?

Cache in `obsidian.nvim` is a JSON file, which stores information of each note, which are placed in the user's workspace.

The information is stored as an array of `obsidian.cache.CacheNote` objects.

The object contains the following fields:

- Absolute path to the note.
- Relative path to the workspace.
- Aliases in the note.
- The time of last modification in seconds.

# How Works

TLDR:

- The cache file is used by pickers.
- The cache file is updated by event handlers from libuv library and on the startup, comparing the last modification time of the notes.

The following sections describe the functionality in more details.

## File Handles

Using the `libuv` library, the `filewatch` module creates single `uv.uv_fs_event_t` handle on Windows and on macOS for the root folder, and a handle for the root folder and one handle for each sub folder on Linux.

Several handles on Linux are used, due to limitation of `UV_FS_EVENT_RECURSIVE` flag. Read the [libuv documentation](https://docs.libuv.org/en/v1.x/fs_event.html) for more.

## Change Events

The created handles fire a change event when a file in the watched folders is changed. This allows us to see all changes which occur in the user's workspace using Neovim or other programs.

The events are filtered and sent to the `cache` module only after 500 milliseconds.
This is done to reduce the overhead of updates of the cache file. For instance, the `rename` command can touch multiple notes and without the delay we would update the cache file for each updated note.

## Updates When Neovim is not Active.

Notes can be updated by programs like like git, syncthing or any cloud storage providers when neovim was not active. For this case, during the startup all notes are checked for last modification time. If the time is different from the time in the cache file, then the file is checked for changes.

## How Pickers use the Cache File

The functionality of the `quick_switch` command was changed in the following way:
the `find_files` uses the cache file as the source, instead of using `rg`.
Aliases, which are placed in the cache file are concatenated after the relative file path with `|` sign.
Example of an entry: `Base/MongoDB Drop Field.md|MongoDB Unset Field|MongoDB Remove Field`

# How to Use

## Add to Ignore

If you use git, syncthing, or other sync solutions, add the cache file (by default it's called `.cache.json`) to ignore (for git is `.gitignore` file) because the absolute paths can differ on each computer and for VCS the cache file can be too big and updated on each file change.

## Enable the Module

By default, the cache module is disabled.

If you use `lazy.nvim`, in your configuration file add the following option:

```lua
cache = {
  enable = true,
},
```

Read the [configuration](https://github.com/obsidian-nvim/obsidian.nvim#%EF%B8%8F-configuration) section for more information.

# Limitations

- New folders which are created on Linux won't be tracked. You can solve this by restart of neovim.
- Several instances of neovim can conflict with each other, because each creates it's own file watch handles.
- Only telescope can read the contents of the cache file at the moment.

# Why

## Why not ripgrep?

To add aliases to the `quick_switch`, I thought about either using ripgrep or saving the aliases to a file or a database (`sqlite`).
But I decided that performance of the ripgrep will subtly degrade over time as the amount of notes increases, but I don't have any metrics to prove this.

But for me it was more intuitive to choose caching, because using already founded aliases is much more quicker than searching them all through the workspace, even though it's performed asynchronously.

## Why JSON

Using SQLite forces the user to install more dependencies. For example, [kkharji/sqlite.lua](https://github.com/kkharji/sqlite.lua) needs both the plugin and SQLite installed on the user's machine.

JSON is not as fast as the SQLite, but it is simple to use and is not depended on 3-rd party packages.
