- [Sort By](#sort-by)
- [Sort Reversed](#sort-reversed)
- [Max Lines](#max-lines)
- [Options](#options)

## Sort By

`opts.search.sort_by` controls how search results are sorted. Valid values are `"modified"` (default), `"created"`, `"accessed"`, and `"path"`. Set to `false` to disable sorting entirely, which can improve performance in large vaults.

## Sort Reversed

`opts.search.sort_reversed` controls the sort direction. Defaults to `true` (newest/last first). Set to `false` to sort ascending.

## Max Lines

`opts.search.max_lines` limits how many lines are parsed when notes are loaded from disk for search. Defaults to `1000`. Set it to `vim.NIL` to parse entire files. Loaded buffers are always parsed in full.

## Options

```lua
---@class obsidian.config.SearchOpts
---
---@field sort_by obsidian.config.SortBy|false
---@field sort_reversed boolean
---@field max_lines integer|?
search = {
  sort_by = "modified",
  sort_reversed = true,
  max_lines = 1000,
}
```
