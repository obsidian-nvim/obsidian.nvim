# Cache Spec v1

Status: draft. Supersedes the description in [Cache.md](Cache.md), which only stored path, aliases, mtime.

## Goals

- Single source of truth for pickers, backlinks, tag search, task views, graph queries.
- Avoid re-scanning the vault with `rg` on every command.
- Survive Neovim restarts; reconcile changes made by external programs (git, syncthing, mobile apps).

Non-goals: full-text search index, content snapshots, attachment binaries.

## Storage

- File: `{stdpath("cache")}/obsidian.nvim/{sha256(vault_path):sub(1, 16)}.json`.
- Format: JSON. UTF-8. One object, top-level `version` + `notes` map keyed by absolute path.
- Schema version: `1`. Bump on breaking change; older files discarded and rebuilt.
- Atomic write: temp file + rename.

```json
{
  "version": 1,
  "vault": "/abs/path/to/vault",
  "generated_at": 1746700000,
  "notes": { "<abs path>": { ...CacheNote } }
}
```

## CacheNote

One entry per markdown file under the vault. The JSON map key is the absolute path; path-derived fields are computed on demand instead of persisted.

| Field | Type | Notes |
|---|---|---|
| `aliases` | string[] | Frontmatter `aliases`, dedup, order preserved. Used for quick switch / link display. |
| `tags` | string[] | Tags, **lowercased**. Nested separator `/` preserved (e.g. `proj/a`). |
| `properties` | object | Frontmatter map. Native YAML types preserved (string/number/bool/list/date/null). |
| `links_out` | Link[] | Outgoing links (wiki + markdown). |
| `tasks` | Task[] | Checkbox items. |
| `mtime` | int | Last modified, seconds since epoch. Cheap mismatch detector. |
| `size` | int | File size in bytes. Cheap mismatch detector. |

Derived from the map key when needed: absolute path, relative path, name, basename, extension, and folder. Empty collections are omitted.

### Property typing

YAML values stored with native types so Bases functions (`date()`, `number()`, `list.filter`, etc.) work without coercion:

- ISO date / `YYYY-MM-DD` → kept as string; promoted via `date()` at query time.
- Numbers stay numeric. Booleans stay boolean. Lists stay lists.
- Unknown / mixed types pass through unchanged.

### Anchor

Mirrors `obsidian.note.HeaderAnchor` (note.lua:1405).

```json
{ "anchor": "#some-header", "header": "Some Header", "level": 2, "line": 12, "parent": "#root" }
```

### Block

```json
{ "id": "block-abc", "line": 42, "text": "raw block line" }
```

### Link

Outgoing references. Backlinks are derived (reverse index built in memory, not stored).

| Field | Type | Notes |
|---|---|---|
| `kind` | `"wiki"` \| `"markdown"` | |
| `raw` | string | Original text, e.g. `[[foo#H\|Foo]]`. |
| `target` | string | Resolved vault-relative path or unresolved name. |
| `resolved` | bool | False if target file not found at index time. |
| `anchor` | string \| null | `#header` portion. |
| `block` | string \| null | `#^block-id` portion. |
| `label` | string \| null | Display label. |
| `line` | int | 1-based source line. |
| `col` | int | Byte column. |
| `embed` | bool | True for `![[...]]` / `![](...)`. |

`target` resolution rule: try vault-shortest, then relative-to-source, then absolute. `resolved=true` requires existing file in cache. Powers Bases `link.linksTo` / `file.hasLink`.

### Task

Checkboxes (see [Checkbox.md](Checkbox.md)). One entry per `- [x]` style list item, including nested.

| Field | Type | Notes |
|---|---|---|
| `state` | string | Single char inside `[ ]`. Empty string = unchecked space. Matches `checkbox.order`. |
| `text` | string | Item text after the checkbox, trimmed. |
| `line` | int | 1-based. |
| `indent` | int | Leading spaces. |

### Tag occurrence (optional, v1.1)

If needed for tag pickers with line jumps, store `tag_occurrences: [{tag, line, col}]`. Otherwise `tags` is sufficient.

## Derived in-memory indexes

Built on load; not persisted.

- `by_id`: id → path.
- `by_alias`: lowercased alias → path[].
- `by_tag`: tag → path[]. Nested-tag lookup expands `proj` → `proj`, `proj/a`, `proj/b` (Bases `file.hasTag` semantics).
- `by_folder`: folder prefix → path[]. Backs `file.inFolder` (matches folder + subfolders).
- `by_property`: property name → path[]. Backs `file.hasProperty`, accelerates filter `note["status"] == "draft"`.
- `backlinks`: target path → {source path, link index}[]. Backs `file.hasLink` reverse direction and `link.linksTo`.
- `unresolved`: target string → source path[].
- `tasks_by_state`: state → {path, line}[].

## Bases compatibility

Mapping of Bases primitives to cache fields:

| Bases | Source |
|---|---|
| `file.name` / `file.basename` / `file.ext` / `file.folder` / `file.path` | derived from map key |
| `file.size` / `file.mtime` | direct fields |
| `file.properties` | `properties` (full frontmatter) |
| `file.tags` | `tags` (lowercased, includes inline + nested) |
| `file.links` | `links_out` |
| `file.hasTag(...)` | `by_tag` + nested expansion |
| `file.hasProperty(name)` | `properties[name] != null` / `by_property` |
| `file.hasLink(other)` | scan `links_out` where `resolved && target == other.path` |
| `file.inFolder(f)` | derived relative path startswith `f/` (or `==` for root file in `f`) |
| `file.asLink(display?)` | build from derived basename + first alias / `display` |
| `link.asFile()` | resolve via cache `path` lookup |
| `link.linksTo(file)` | reverse via `backlinks` |

Functions that operate purely on values (`date.format`, `string.contains`, `list.map`, regex, math, etc.) are pure runtime — cache only needs to surface the right typed value.

Out of cache scope (computed at query time):
- Date arithmetic, durations, `now()`/`today()`.
- Formula evaluation, `if()`, `reduce()`.
- HTML / image / icon rendering.

## API surface (ORM-style)

Consumers never touch JSON or SQL directly. Public module is `obsidian.cache` exposing repository + query objects. Backend swappable via config (`cache.backend = "json" | "sqlite" | custom`).

### Top-level

```lua
local cache = require("obsidian.cache")

cache.setup { backend = "json" }   -- or backend = "sqlite"

cache.notes      -- Repository<CacheNote>
cache.tasks      -- Repository<Task>
cache.links      -- Repository<Link>
cache.tags       -- Repository<TagRow>
```

### Repository

CRUD + query builder. Mirrors typical ORM (Active Record / Diesel / Prisma feel). All read methods sync; writes go through unit-of-work then flush.

```lua
---@class obsidian.cache.Repository<T>
repo:get(pk)                     -- by primary key (path for notes, (path,line) for tasks)
repo:find(pk)                    -- get or nil
repo:all()                       -- iterator
repo:where(predicate_or_table)   -- returns Query<T>
repo:count(predicate?)
repo:insert(row)
repo:update(pk, patch)
repo:upsert(row)
repo:delete(pk)
repo:transaction(fn)             -- atomic batch
```

### Query

Lazy. Composes; executes on `:fetch()` / `:first()` / `:iter()`.

```lua
cache.notes
  :where { folder = "Daily" }
  :where(function(n) return n.properties.status == "draft" end)
  :tagged("work")           -- sugar for tag predicate
  :linked_to(other_path)    -- backlink sugar
  :order_by("mtime", "desc")
  :limit(50)
  :fetch()                  -- list of CacheNote
```

Query operators: `eq`, `ne`, `lt`, `lte`, `gt`, `gte`, `in_`, `like`, `matches` (regex), `contains` (list/string), `between`. Predicates compile to backend-native ops where possible (SQL `WHERE`, JSON filter loop).

### Sugar helpers (Bases-aligned)

```lua
note:has_tag("proj")         -- nested-aware
note:has_property("status")
note:has_link(other)
note:in_folder("Daily")
note:as_link { display = "..." }
note:backlinks()             -- iterator over Link
note:tasks { done = false }  -- filtered task list
```

### Events

```lua
cache.on("note:changed", function(path, old, new) end)
cache.on("note:deleted", ...)
cache.on("task:changed", ...)
```

Pickers, backlinks panel, tasks view subscribe; never poll.

## Backends

Single trait. Backend is dumb storage; query planning + indexing live above so semantics stay identical across backends.

```lua
---@class obsidian.cache.Backend
backend:open(opts)
backend:close()
backend:get(table, pk)
backend:put(table, pk, row)
backend:delete(table, pk)
backend:scan(table, filter?)     -- iterator
backend:batch(ops)               -- atomic
backend:meta_get(key) / meta_put(key, value)   -- schema version, generated_at
```

Built-in backends:

| Backend | Storage | Notes |
|---|---|---|
| `json` (default) | single JSON file under `stdpath("cache")`, atomic rename | Zero deps. Loads fully into memory. Good ≤ 10k notes. |
| `sqlite` | database under `stdpath("cache")` via `sqlite.lua` (optional dep) | Lazy scan, predicate pushdown, partial loads. For big vaults. |
| `memory` | in-process only | Tests + ephemeral sessions. |
| custom | user-provided table | Register via `cache.register_backend("name", impl)`. |

Capability flags backend declares: `pushdown_filter`, `pushdown_order`, `partial_load`, `transactional`. Query layer falls back to in-Lua filtering when a flag is missing.

### SQLite schema (sketch)

```sql
CREATE TABLE notes (
  path TEXT PRIMARY KEY,
  mtime INTEGER,
  size INTEGER,
  properties JSON
);
CREATE TABLE aliases   (path TEXT, alias TEXT, PRIMARY KEY(path, alias));
CREATE TABLE tags      (path TEXT, tag TEXT, PRIMARY KEY(path, tag));
CREATE TABLE links     (src TEXT, target TEXT, kind TEXT, anchor TEXT, block TEXT,
                        embed INTEGER, line INTEGER, col INTEGER, resolved INTEGER);
CREATE TABLE tasks     (path TEXT, line INTEGER, state TEXT, indent INTEGER,
                        text TEXT, PRIMARY KEY(path, line));
CREATE TABLE anchors   (path TEXT, anchor TEXT, header TEXT, level INTEGER, line INTEGER);
CREATE TABLE blocks    (path TEXT, id TEXT, line INTEGER, PRIMARY KEY(path, id));
CREATE INDEX ON tags(tag); CREATE INDEX ON links(target);
```

JSON backend serializes the same logical tables under one root object; field names match.

### Backend swap rules

- Schema version tracked via `meta_get("version")`; mismatch → drop + rebuild.
- Switching backend in config = full reindex from vault. No JSON↔SQLite live migration.
- Public API unchanged across backends; tests exercise both via parameterized fixtures.

## Update flow

1. Startup: load JSON. For each note, stat the file. If missing → drop. If `mtime` or `size` differ → reparse. Walk vault for new files.
2. Runtime: `filewatch` (libuv) emits events. Coalesce 500 ms. For each touched path:
   - deleted → remove entry, invalidate dependents.
   - created/modified → reparse, replace entry.
3. Save: debounced flush to disk (e.g. 2 s idle) and on `VimLeavePre`.

Parsing reuses `obsidian.Note` loader plus a lightweight task/link extractor; no buffer required.

## Concurrency

- Multiple Neovim instances: last-writer-wins on the JSON file. Each instance keeps its own watcher (documented limitation in [Cache.md](Cache.md)).
- Optional lock file next to the cache file with PID + mtime; stale > 60 s ignored.

## Migration

`version` bump → discard, rebuild from scratch. No in-place migration in v1; cache is purely derived state.

## Limitations carried from v1 design

- New Linux subdirectories not auto-watched until restart.
- Only consumers wired in v1: telescope picker, backlinks, tasks view. Snacks/fzf/mini consumers added incrementally.
- Hash is best-effort; mtime+size remains the primary change signal.

## Open questions

- Per-note partial cache files vs single JSON (write amplification at scale).
- Whether to persist backlinks directly to skip rebuild on startup for very large vaults.
- Compression (e.g. gzip) once vaults exceed ~10k notes.
- Bases formula caching: memoize per-note formula results keyed by `(formula hash, mtime)`?
- Date detection in YAML: auto-promote `YYYY-MM-DD` strings to date objects on load, or only on `date()` call?
- Query DSL: closure-based predicates vs string DSL (`:where("tags has 'x'")`) — closures simpler, strings cheaper to push down to SQL.
- Migration tool between backends (one-shot CLI) vs always rebuild from vault.
