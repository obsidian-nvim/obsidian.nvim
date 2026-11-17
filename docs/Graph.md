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
## Open and interact with the graph

Open the vault graph with `:Obsidian graph`. Use `:Obsidian graph %` for the current note's local graph, or pass a note path or vault folder. Enable `cache.enabled` to use the graph. Attachment nodes are hidden by default. Turn on the settings panel's **Attachments** toggle to display them as yellow circles.

## Node context menu

Right-click an existing note node for:

- **Open**: open the note in Neovim.
- **Copy path**: copy its absolute path to Neovim's system clipboard (`+`). This requires a clipboard provider on the Neovim host.

Tag and missing-note nodes have no note actions. Use Up/Down, Home/End, and Enter/Space within the menu; Escape dismisses it. Left-click still opens notes, with Shift for a split, Ctrl/Cmd for a vertical split, or Alt for a tab.

## Registering actions

Register whole-note actions from Lua. You do not need to change the browser UI:

```lua
local graph = require "obsidian.core-plugins.graph"

local unregister = graph.register_action {
  name = "show_path",
  title = "Show path",
  cond = function(ctx)
    return ctx.node.folder == "projects"
  end,
  fn = function(ctx)
    vim.notify(ctx.path)
  end,
}

-- Remove this registration when no longer needed.
-- unregister()
```

Fields:

- `name`: unique, nonempty string. Duplicate registrations raise an error.
- `title`: string or `function(ctx)` returning a string.
- `cond`: optional `function(ctx)` returning whether to show the action. Neovim checks it again before execution.
- `fn`: `function(ctx)` to execute. Raise an error to report a failure in the browser. The HTTP response confirms callback completion, not the completion of any asynchronous work it starts.

Context:

- `ctx.node`: a copy of the server-resolved `obsidian.graph.Node`, including its graph ID, title, folder, tags, and aliases. The graph ID is the vault-relative path without its Markdown suffix, not a frontmatter ID.
- `ctx.path`: the note's absolute path.

The menu lists actions in registration order, after the built-in `open` and `copy_path` actions. Registrations survive graph server restarts. Call the returned unregister function to remove a custom action; repeated calls are safe.

Titles, conditions, and callbacks run on Neovim's main loop. Conditions and titles should not modify notes. A target must still be an existing note when an action executes.

### Adapting code actions

Use `ctx.path` to target the clicked note. It may differ from the current Neovim buffer. Existing actions such as `move_note`, `merge_note`, and `delete_note` use the current buffer, so do not register them as callbacks without adapting them to accept an explicit target. Capture that target in asynchronous picker or prompt callbacks too.

Keep cursor- and selection-dependent actions in the editor. Once a whole-note operation accepts an explicit target, a graph registration can call it without browser changes.
