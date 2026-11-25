---
title: "Search"
tags:
  - search
  - configuration
---

- [Sort By](#sort-by)
- [Sort Reversed](#sort-reversed)
- [Max Lines](#max-lines)
- [Options](#options)
- [See also](#see-also)

## Sort By

`opts.search.sort_by` controls how file results are sorted. Valid values are `"modified"` (default), `"created"`, `"accessed"`, `"frecency"`, and `"path"`. Set to `false` to disable sorting entirely, which can improve performance in large vaults.

`"frecency"` ranks notes by accumulated visits, weighting recent visits more heavily. While this option is selected, visits are recorded when a note buffer is entered, with a 30-second per-note cooldown. Visit history is persisted separately from the optional metadata cache, retained for 90 days, and capped at 100 visits per note. Higher scores sort first when `sort_reversed` is `true` (the default). Picker fuzzy matching can still reorder candidates as you type.

## Sort Reversed

`opts.search.sort_reversed` controls the sort direction. Defaults to `true` (descending by sort value); `"frecency"` puts higher scores first. Set to `false` to sort ascending. Equal frecency scores use normalized path order as a stable tie-break.

## Max Lines

`opts.search.max_lines` limits how many lines of each file ripgrep will search. Defaults to `1000`. Set to `nil` to search entire files.

## Options

```lua
---@class obsidian.config.SearchOpts
---
---@field sort_by obsidian.config.SortBy|false
---@field sort_reversed boolean
---@field max_lines integer
search = {
  sort_by = "modified", -- also: "created", "accessed", "frecency", "path", or false
  sort_reversed = true,
  max_lines = 1000,
}
```

## See also

[[Completion]] · [[Cache]] · [[Tag]]
