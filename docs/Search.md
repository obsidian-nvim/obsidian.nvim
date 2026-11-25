---
title: "Search"
tags:
  - search
  - configuration
---

- [Current scope](#current-scope)
- [Search terms](#search-terms)
- [Search operators](#search-operators)
- [Search properties](#search-properties)
- [Case sensitivity](#case-sensitivity)
- [Search results](#search-results)
- [Regular expressions](#regular-expressions)
- [Lua API](#lua-api)
- [Configuration](#configuration)
- [Options](#options)
- [Planned work](#planned-work)
- [See also](#see-also)

Search has two entry points with different query languages today:

- `:Obsidian search [QUERY]` searches note content with ripgrep and your configured picker. It does **not** interpret the Obsidian query language described below. `obsidian://search` links use this same grep path.
- Selecting a saved **search bookmark** with `:Obsidian bookmarks` evaluates an Obsidian-style query and presents matching files with the configured picker. The query engine is also available through Lua.

This page follows the topics in [Obsidian's Search documentation](https://help.obsidian.md/plugins/search), but describes the subset implemented in `obsidian.nvim`, not full app compatibility. A dedicated search UI and embedded query results are planned, not implemented.

## Current scope

Query execution requires the [[Cache]] to be enabled. It waits for startup validation before searching the cached vault. Content queries additionally require `rg` on your `PATH`; metadata-only queries, such as `file:meeting`, `tag:work`, or `[status:Draft]`, do not start ripgrep.

The searchable file set includes `.md`, `.markdown`, `.qmd`, `.base`, `.canvas`, and `.excalidraw` files. Generic formats are searched as raw text, not as parsed canvas nodes or Markdown notes. `file:` and `path:` currently search only this set, **not every attachment or arbitrary file in the vault**.

Files excluded by `file.ignore_filters` and internal vault/Git files do not appear in the cache-backed query results. Obsidian app exclusion settings are not imported. See [[File#Ignore Filters|Ignore Filters]].

Queries read saved files on disk. They do not overlay unsaved buffer edits. Content predicates currently read complete lines for the entire searchable file set within the query root, then evaluate the query in Lua; they are not indexed full-text searches.

## Search terms

Unquoted terms are literal substrings, matched independently within each file. By default a term can match the filename or file content; use `path:` to search directory components and `content:` to restrict a term to content.

| Query | Meaning |
| --- | --- |
| `meeting work` | Both terms must match the file, not necessarily the same line. |
| `"star wars"` | Match this literal phrase on one line, or in the filename. |
| `meeting OR work` | Either term may match. `OR` must be uppercase. |
| `meeting work OR meetup personal` | Implicit AND binds more tightly than OR. |
| `meeting (work OR meetup) personal` | Parentheses control grouping. |
| `meeting -work` | Require `meeting` and exclude files matching `work`. |
| `meeting -work -meetup` | Exclude either unwanted term. |
| `meeting -(work meetup)` | Exclude files matching both grouped terms. |

Inside a quoted phrase, escape quotes with a backslash: `"they said \"hello\" to each other"`. Escape a literal backslash as `\\`. Quoting also lets you search syntax characters literally, for example `"/work/"` or `"(draft)"`.

An empty query matches all searchable files. It does not open recent-search history. Unknown operator names are treated as literal terms, rather than rejected as unsupported operators.

## Search operators

Operators can contain a term, a quoted phrase, or a parenthesized subquery, for example `task:(call OR email)`.

| Operator | Current behavior | Example |
| --- | --- | --- |
| `file:` | Literal substring in the filename, including its extension. Limited to searchable file types. | `file:202209` |
| `path:` | Literal substring in the vault-relative path. Limited to searchable file types. | `path:"Daily notes/2022-07"` |
| `content:` | Search file content, excluding the filename. Includes frontmatter and code text. | `content:"happy cat"` |
| `match-case:` | Match the enclosed expression case-sensitively. | `match-case:HappyCat` |
| `ignore-case:` | Match the enclosed expression case-insensitively. | `ignore-case:ikea` |
| `tag:` | Exact cached tag match, with an optional leading `#`. Includes frontmatter tags; ignores tags in code. | `tag:#work` |
| `line:` | At least one source line must satisfy the enclosed expression. | `line:(mix flour)` |
| `block:` | At least one group of nonblank source lines must satisfy the expression. This is an approximation of Markdown blocks. | `block:(dog cat)` |
| `section:` | At least one section split at an ATX heading (`# Heading`) must satisfy the expression. This is not yet syntax-aware. | `section:(dog cat)` |
| `task:` | Search individual cached task-marker lines. Continuation lines and child blocks are not included. | `task:(call OR email)` |
| `task-todo:` | As above, restricted to a space checkbox state (`[ ]`). | `task-todo:call` |
| `task-done:` | As above, restricted to `[x]` or `[X]`. | `task-done:call` |

`-line:(mix flour)` matches files where **no** line satisfies both terms. `line:(mix -flour)` instead requires a line containing `mix` but not `flour`.

Tag matching does not treat a substring or suffix as a tag: `tag:work` does not match `#myjob/work`. Currently it also does not expand `#work` to descendant tags such as `#work/project`. Boolean expressions inside `tag:` are evaluated against one tag at a time, not the entire tag collection.

`block:` splits on blank lines, including blank lines inside fenced code. `section:` splits on heading-like source lines even inside code fences, does not recognize setext headings, and does not retain parent-section scope across child headings. Neither operator yet uses the cached parsed Markdown ranges.

## Search properties

Properties come from Markdown YAML frontmatter, not arbitrary text that resembles a property.

| Query | Current behavior |
| --- | --- |
| `[aliases]` | Require a matching property name. |
| `[status:Draft]` | Require a matching property name and a value containing `Draft`. |
| `[status:Draft OR Published]` | Match either value expression. |
| `[rating:null]` | Require an existing property whose YAML value is null. |
| `[duration:<5]` | Compare a property value with `5`. |
| `[duration:>=5]` | Inclusive comparison is also supported. |

Both property names and values accept grouping, negation, `OR`, and quoted phrases. Names and string values currently use substring matching, **not exact property-key or whole-value equality**; quoting makes a phrase literal but does not change this to equality.

Lists and maps are flattened into strings for value matching, including map keys. A value subquery is evaluated against each flattened string separately: `[aliases:(Alice Bob)]` does not combine separate list entries. Null is special only as the entire value expression (`[rating:null]`), not inside a compound value query. Empty quotes (`""`) and empty lists (`[]`) are not null.

Comparisons use numbers when both operands convert to numbers; otherwise compatible string operands use case-folded lexical ordering. Comparisons nested inside compound value expressions do not yet have comparison semantics. Typed property comparisons and collection-wide boolean/null semantics need further compatibility work.

## Case sensitivity

Queries are case-insensitive by default, including Unicode case folding through Neovim. Use `match-case:` or `ignore-case:` around a term or group to override this locally:

```text
match-case:HappyCat
match-case:(HappyCat OR Work)
match-case:(HappyCat ignore-case:work)
```

There is no query-wide Match case UI toggle yet. The legacy grep command follows its picker/ripgrep behavior instead of these query operators.

## Search results

The engine returns **one result per matching file**, with one representative location, not every occurrence. Filename matches rank above content matches; ties are ordered by case-folded vault-relative path. Negated and metadata-only results may have no content context and fall back to a file-opening location.

Search bookmarks display these results through the configured picker, with file previews and multi-selection. This is a result selector, not an editable, live Obsidian-query search UI. Query errors are reported instead of falling back to grep.

The query engine does not yet offer Obsidian's filename/modified-time/created-time sort choices, grouped occurrences, context toggles, or a Copy search results action. Existing `search.sort_by` and `search.sort_reversed` settings do not change query-engine ranking.

## Regular expressions

**Regular expressions are deliberately unsupported in the first query-engine PR.** Slash-delimited queries such as `/\d{4}-\d{2}-\d{2}/`, `path:/2022/`, and `[status:/Draft/]` return an explicit unsupported-feature error. Use quotes for literal slash-containing text: `path:"Daily notes/"` or `content:"/draft/"`.

Obsidian uses JavaScript-flavored regular expressions. Vim regex, Lua patterns, and ripgrep regex have different syntax and behavior; accepting one of them as an Obsidian regex would silently produce incompatible results. This restriction applies to the query engine, not to regex facilities already provided by the legacy grep command or its picker.

A later implementation could use a JavaScript engine, for example through a Node process or remote plugin. No backend or Node dependency is committed to yet. Syntax, flags, Unicode behavior, match offsets, cancellation, and protection against expensive patterns must be specified and tested before enabling regex. Pattern input must be treated as data, not evaluated as JavaScript source.

## Lua API

Enable the cache in your plugin configuration:

```lua
require("obsidian").setup {
  cache = { enabled = true },
}
```

Run a query asynchronously:

```lua
local Query = require "obsidian.search.query"

local cancel = Query.search("tag:#work -[status:Done]", nil, function(results, err)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  for _, result in ipairs(results) do
    print(result.document.relative_path, result.line, result.col)
  end
end)

-- Call cancel() if the caller no longer needs the results.
```

The options table accepts:

- `root`: a directory within the active cached vault; defaults to that vault. It filters files, but `path:` still matches vault-relative paths.
- `include_non_markdown = false`: restrict results to Markdown note types.
- `allow_incomplete = true`: tolerate some unfinished delimiters/operator values while typing. It does not accept every incomplete expression, and does not enable regex.

`Query.parse(query)` returns an AST or `nil, err` without searching. `Query.search(query, opts, callback)` calls back with results and an optional error, and returns a cancellation function. Errors include invalid queries, a disabled cache, roots outside the cached vault, missing ripgrep for content queries, and repeated cache changes during execution. A cache-generation change retries once before failing. Cancellation suppresses delivery of results.

Result `line` and `col` are one-based byte coordinates. `end_col`, when present, is a one-based exclusive end column. These are picker/quickfix-facing coordinates, not internal `obsidian.Range` coordinates. `context` is optional, and metadata-only matches do not load source lines.

## Configuration

These existing options are shared by legacy search/note-loading features; they are not query UI settings.

### Sort By

`opts.search.sort_by` controls sorting where supported by the legacy search backend. Valid values are `"modified"` (default), `"created"`, `"accessed"`, and `"path"`. Set it to `false` to disable backend sorting. Query-engine results use match ranking instead.

### Sort Reversed

`opts.search.sort_reversed` controls the backend sort direction. Defaults to `true` (newest/last first). Set it to `false` to sort ascending. This does not reverse query-engine ranking.

### Max Lines

`opts.search.max_lines` defaults to `1000` and limits note loading in search helpers that use it. It is **not** a general ripgrep content-search limit. The query engine reads complete files and does not apply this limit; otherwise negation and scoped predicates could miss content beyond the cutoff.

## Options

```lua
---@class obsidian.config.SearchOpts
---
---@field sort_by obsidian.config.SortBy|false
---@field sort_reversed boolean
---@field max_lines integer
search = {
  sort_by = "modified",
  sort_reversed = true,
  max_lines = 1000,
}
```

## Planned work

These are TODOs, not available features or commitments to include everything in the first PR.

### Minimal first PR

- [x] Parse literal terms, phrases, implicit AND, `OR`, grouping, and negation.
- [x] Evaluate the documented operator names and basic property predicates against the validated cache universe.
- [x] Run saved-search bookmarks through the query engine and existing result picker.
- [x] Report regex as unsupported instead of interpreting JavaScript patterns as Vim regex.
- [x] Document supported behavior separately from compatibility gaps and future UI work.
- [x] Run asynchronous query tests in a child Neovim so parent-runner scheduling cannot finish before assertions.
- [ ] Add regressions for cancellation before cache readiness/during ripgrep, cache-generation retry/failure, invalid roots, exclusions, and missing/failed ripgrep at the query API boundary.
- [ ] Verify source coordinates for filename, path, tag, task, metadata-only, and negated matches; avoid presenting non-content offsets as content columns.
- [ ] Add compatibility fixtures for property-key/value matching, null/list predicates, nested scopes, and task states. Either narrow the promised subset or resolve differences before claiming app compatibility.

### Search UI

- [ ] Build a dedicated editable query UI using this engine, with debouncing, cancellation, stale-result suppression, progress, parse errors, and an explicit empty/no-results state.
- [ ] Decide how `:Obsidian search` and `obsidian://search` adopt query semantics without silently breaking existing grep workflows; retain an explicit grep entry point if needed.
- [ ] Seed queries from selected editor text and offer recent-search history for empty input.
- [ ] Add a global Match case toggle and explain-search-term output.
- [ ] Group results by file, show all occurrences with highlights, support collapse/expand and more-context controls, and navigate to matches.
- [ ] Add filename ascending/descending, modified-time, and created-time sorting, with deterministic ties and documented missing-stat behavior.
- [ ] Add Copy search results with a documented output/link format.
- [ ] Support creating/editing saved search bookmarks from the query UI.

### Embedded search results

- [ ] Recognize fenced `query` blocks and render results without rewriting the note's source text.
- [ ] Reuse the query engine and its errors; do not introduce a second query-language implementation.
- [ ] Navigate from embedded matches to their source locations, with defined context, ordering, and result limits.
- [ ] Refresh on relevant vault/query changes, cancel obsolete requests, and clean up on buffer detach or workspace changes.

The intended syntax follows Obsidian, but currently remains an ordinary code block:

````markdown
```query
embed OR search
```
````

### Compatibility and performance

- [ ] Search arbitrary vault files/attachments by `file:` and `path:` without parsing or reading binary content.
- [ ] Define canvas/non-Markdown content semantics rather than relying on raw serialized text.
- [ ] Use parsed Markdown ranges for blocks/sections, including fenced code, setext headings, lists, and nested headings; search full task blocks and define custom checkbox-state behavior.
- [ ] Resolve hierarchical-tag behavior and collection-wide tag subqueries against Obsidian fixtures.
- [ ] Resolve property equality, typed comparisons, compound comparisons/null predicates, and collection-wide boolean semantics against Obsidian fixtures.
- [ ] Define unsaved-buffer overlays and exclusion/workspace behavior for both UI and embedded queries.
- [ ] Prune candidates before loading content where logically safe, bound memory/result sizes, and measure large-vault latency before enabling live queries.
- [ ] Evaluate an optional JavaScript regex backend only after the non-regex query behavior is stable; keep it out of the initial PR.

## See also

[[Bookmarks]] · [[Cache]] · [[File]] · [[Completion]] · [[Embeds]] · [[Tag]]
