- [Ignore Filters](#ignore-filters)
- [Options](#options)

## Ignore Filters

The `file.ignore_filters` option lets you ignore specific files or
directories from being processed by obsidian.nvim. This is useful when you have
markdown files in your vault that shouldn't be treated as Obsidian notes.

> [!IMPORTANT]
> Users should use simple gitignore-style globs without modifiers.
> Ripgrep (rg) compatibility is not guaranteed.

### Pattern Syntax

The ignore filters use gitignore-style pattern matching:

- `archive` - matches any file or directory named "archive"
- `archive/` - matches only directories named "archive"
- `private/**` - matches all files under "private" directory
- `*.bak.md` - matches any file ending with ".bak.md"
- `/README.md` - matches "README.md" only at vault root
- `**/draft.md` - matches "draft.md" at any depth
- `drafts/*.md` - matches markdown files directly under "drafts" (not in subdirectories)

> [!IMPORTANT]
> All patterns must be relative to the workspace root.

### Examples

```lua
{
  file = {
    ignore_filters = {
      "archive",           -- ignore the "archive" directory
      "private/**",        -- ignore everything under "private"
      "*.bak.md",          -- ignore backup files
      "slides/present.md", -- ignore a specific file
    },
  },
}
```

### Behaviour

Files in the ignore list will:
- not have the LSP attached
- not have keymaps registered
- not have frontmatter processed
- not appear in search results
- not be included when iterating over vault files

## Options

```lua
---@class obsidian.config.FileOpts
---
--- A list of gitignore-style glob patterns to ignore files and directories.
--- Users should use simple gitignore style globs without modifiers,
--- and ripgrep compatibility is not guaranteed.
---@field ignore_filters? string[]
file = {
  ignore_filters = {},
}
```
