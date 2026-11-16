---
title: "Graph"
tags:
  - api
---

`require("obsidian.graph")` builds on-disk vault snapshots for diagnostics and
visualization consumers. It does not render a graph or maintain a live index.
Rebuild the snapshot after files change. Returned tables are detached copies.

## Build a snapshot

With an enabled, ready metadata cache, construction performs no filesystem reads:

```lua
local graph = require("obsidian.graph").from_cache()
```

Without the cache, use the asynchronous vault loader:

```lua
local cancel = require("obsidian.graph").from_vault_async(function(graph, err)
  if not graph then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  local data = graph:to_table { include_tag_nodes = true }
  -- Send data.nodes and data.links to your consumer.
end)

-- Optional: cancel() stops pending work and suppresses the callback.
```

Pass `{ dir = "/path/to/vault" }` as the second argument to select another root;
otherwise the loader uses the active workspace root. It enumerates files with
ripgrep and falls back to the filesystem walker when ripgrep is unavailable.
Parsing runs in batches and reads each note once, including content beyond
`search.max_lines`. A read, parse, or ripgrep error returns `nil, err`, not a
partial graph.

Both routes include supported notes and attachments, including isolated files,
templates, dotfiles and gitignored files. The loader follows the cache inventory
rules rather than ordinary text-search visibility: configured `file.ignore_filters`,
`.git`, and the configured Obsidian configuration directory are excluded.
Neither constructor overlays unsaved buffers. A scan is not an atomic filesystem
transaction; refresh after concurrent edits.

## Nodes, links and resolution

`graph:to_table()` returns sorted `nodes` and deduplicated, directed `links`.
Attachments are always included. Tags are opt-in via `include_tag_nodes`.

IDs preserve file extensions and separate namespaces:

- `note:projects/Plan.md`
- `attachment:assets/diagram.png`
- `tag:project/planning`
- `missing:note:Unwritten.md`
- `missing:attachment:assets/absent.png`

File nodes contain absolute `path`, vault-relative `folder`, `title`, `aliases`,
`tags`, and `exists`. Tags use the shared tag normalizer: case-insensitive,
without a leading `#`, with nested tag names preserved.

Exact paths take precedence over note IDs, aliases, and basename matches.
Notes prefer source-relative paths, then vault-relative paths, then symbolic
references. `./` and `../` references do not fall back to unrelated files;
references escaping the vault are excluded. Case-exact paths win before
case-insensitive lookup. Extensionless matches across multiple note formats are
ambiguous; `.base` requires its extension.

Bare attachment names first check the configured attachment folder, including
source-relative folders such as `./assets`. Other matches use attachment paths
or unique basenames. Multiple existing source/root attachment paths are
ambiguous. In-vault file URIs and absolute filesystem paths resolve against the
snapshot; external URIs are excluded. Resolution does not perform filesystem
lookups.

Self-links do not produce edges. Missing note and attachment targets produce
missing nodes. Ambiguous references produce neither edges nor missing nodes.
Heading/block fragments do not create separate nodes; this API diagnoses missing
files, not missing fragments.

## Diagnostics

```lua
local broken = graph:broken_links()
local ambiguous = graph:ambiguous_links()
local notes = graph:orphan_files()
local files = graph:orphan_files {
  include_attachments = true,
  include_tag_nodes = true,
}
```

Broken and ambiguous results retain the source node ID, absolute source path,
original target, link kind, raw source, and line/column when available. Ambiguous
results also contain sorted candidate node IDs.

Orphans have no resolved incoming or outgoing connections. By default the method
returns only note paths; `include_attachments` also returns unreferenced
attachments. Resolved attachment links count as connections. Tag memberships
count only with `include_tag_nodes`; self-links, missing links and ambiguous
references do not count. Results are sorted absolute paths. These diagnostics
are not authorization to delete files: other applications or unsupported file
types may refer to them.
