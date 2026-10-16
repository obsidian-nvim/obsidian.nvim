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

`opts.search.sort_by` controls how search results are sorted. Valid values are `"modified"` (default), `"created"`, `"accessed"`, and `"path"`. Set to `false` to disable sorting entirely, which can improve performance in large vaults.

## Sort Reversed

`opts.search.sort_reversed` controls the sort direction. Defaults to `true` (newest/last first). Set to `false` to sort ascending.

## Max Lines

`opts.search.max_lines` limits how many lines are parsed when notes are loaded from disk for search. Defaults to `1000`. Set it to `vim.NIL` to parse entire files. Loaded buffers are always parsed in full.

## Structured Search

The search API exposes note-, heading-, and block-level results separately:

```lua
local search = require "obsidian.search"
local notes = search.find_notes("api")
local headings = search.find_headings("http-api")
local blocks = search.find_blocks("^block-id")
```

`find_headings()` returns `{ note, heading }` matches, where `heading` includes its section and source location. `find_blocks()` returns `{ note, section, blocks }` matches for block-candidate sections and explicit block IDs. Both use the cache when available and otherwise parse notes from disk; their options include `dir`, `ignore_case`, and the usual sort settings. An empty query returns all matches in that domain.

For combined results, call the relevant searches and merge their results. `find_notes()` searches note references (IDs, aliases, names, and paths). Note heading and block structures are lazy: reading `note.sections` or `note.anchor_links` loads heading data, while reading `note.blocks` or `note.block_candidates` loads block data. The loaded structures are cached on the `Note`; no preload option is required.

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

## See also

[[Completion]] · [[Cache]] · [[Tag]]
