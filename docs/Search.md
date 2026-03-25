[Options](#Options)

## Sort By

`opts.search.sort_by` controls how search results are sorted. Valid values are `"modified"` (default), `"created"`, `"accessed"`, and `"path"`. Set to `false` to disable sorting entirely, which can improve performance in large vaults.

## Sort Reversed

`opts.search.sort_reversed` controls the sort direction. Defaults to `true` (newest/last first). Set to `false` to sort ascending.

## Max Lines

`opts.search.max_lines` limits how many lines of each file ripgrep will search. Defaults to `1000`. Set to `nil` to search entire files.

## Options

```lua
---@alias obsidian.config.SortBy "modified" | "created" | "accessed" | "path"

---@class obsidian.config.SearchOpts
---@field sort_by obsidian.config.SortBy|false
---@field sort_reversed boolean
---@field max_lines integer
search = {
  sort_by = "modified",
  sort_reversed = true,
  max_lines = 1000,
}
```
