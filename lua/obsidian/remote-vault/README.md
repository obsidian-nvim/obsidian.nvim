# Remote vault design

`obsidian.remote-vault` is a pull-only materializer for remote reading queues. It is intentionally separate from `obsidian.sync`: vault sync replicates files, while a remote vault turns API resources into owned Markdown notes. Every remote vault is an independent Obsidian workspace at an explicitly configured absolute path, not a directory inside the default vault.

## Built-in adapters

GitHub issues and feed.nvim queries have built-in constructors. Each remote vault requires its own absolute workspace path outside every existing Obsidian workspace:

```lua
local remote = require "obsidian.remote-vault"

remote.setup {
  vaults = {
    remote.adapters.github {
      repo = "owner/repository",
      path = vim.fn.expand "~/remote-vaults/github-issues",
      -- Default shown for clarity:
      name = "github-issues",
      state = "open",
      limit = 100,
      -- Optional gh filters:
      assignee = "@me",
      labels = { "reading" },
      removal = "archive",
    },

    remote.adapters.feed {
      path = vim.fn.expand "~/remote-vaults/rss",
      -- Any feed.nvim query. Items that leave this result are removed according
      -- to the configured strategy, so define the collection deliberately.
      query = "+unread @6-months-ago",
      name = "rss",
      removal = "archive",
    },
  },
}
```

The GitHub adapter uses authenticated `gh issue list` and `gh issue view` calls. The feed adapter reads feed.nvim's current database; run `:Feed update` first when network freshness is required. Its default query is `+unread`.

```vim
:Obsidian remote sync github-issues
:Obsidian remote sync rss
```

Both constructors return regular `Vault` objects, so callers can mix them with custom adapters. Call `remote.setup()` after `require("obsidian").setup()`, or from Obsidian's `post_setup` callback. Setup creates missing remote roots and appends strict workspaces to `Obsidian.workspaces` without changing the active workspace. Names and paths must not collide with or nest inside any existing workspace.

## Custom adapter example: YouTube Watch Later

```lua
local remote = require "obsidian.remote-vault"

remote.setup {
  vaults = {
    {
      name = "yt-watch-later",
      path = vim.fn.expand "~/remote-vaults/youtube-watch-later",
      removal = "archive", -- "archive" (default), "delete", or "keep"

      -- Both adapter methods are asynchronous and error-first. They must call
      -- callback exactly once. Any return value is ignored; completion always
      -- happens through the callback.
      list = function(ctx, callback)
        vim.system({ "yt-dlp", "--flat-playlist", "--dump-single-json", WATCH_LATER_URL }, { text = true }, function(out)
          if out.code ~= 0 then
            return callback(out.stderr)
          end
          local playlist = vim.json.decode(out.stdout)
          callback(nil, vim.tbl_map(function(video)
            return {
              id = video.id,
              title = video.title,
              url = "https://www.youtube.com/watch?v=" .. video.id,
              -- Must change when any list-visible data relevant to the note changes.
              revision = tostring(video.timestamp or video.release_timestamp or video.title),
              data = video,
            }
          end, playlist.entries))
        end)
      end,

      fetch = function(summary, ctx, callback)
        vim.system({ "yt-dlp", "--dump-single-json", summary.url }, { text = true }, function(out)
          if out.code ~= 0 then
            return callback(out.stderr)
          end
          local video = vim.json.decode(out.stdout)
          callback(nil, {
            id = summary.id,
            revision = summary.revision,
            title = video.title,
            url = video.webpage_url,
            added_at = summary.added_at,
            updated_at = video.upload_date,
            metadata = {
              channel = video.channel,
              duration = video.duration,
            },
            content = {
              "# " .. video.title,
              "",
              video.webpage_url,
              "",
              video.description or "",
            },
          })
        end)
      end,
    },
  },
}
```

Run it with:

```vim
:Obsidian remote sync yt-watch-later
```

With no name, `:Obsidian remote sync` opens a picker. The Lua API also supports:

```lua
remote.sync("yt-watch-later", { dry_run = true }, function(err, report)
  -- report.plan.create / update / unchanged / remove
end)
```

Integrations can call `remote.register(spec)` instead of owning setup.

## Adapter contract

An adapter has two read operations:

1. `list(ctx, callback)` returns cheap `ResourceSummary` values for the complete current remote collection.
2. `fetch(summary, ctx, callback)` hydrates one summary into a `Resource` only when it is new or changed.

A summary requires a stable provider-scoped `id`. `revision` is strongly recommended. Equal non-nil revisions skip `fetch`; absent revisions force a fetch every sync. A revision therefore needs to cover title, URL, content, and metadata used by the note—not just the remote object's edit timestamp.

A resource can contain:

```lua
{
  id = "stable-id",       -- required; must match the summary
  revision = "opaque-v2",
  title = "Readable title",
  url = "https://...",
  added_at = "2026-03-01T10:00:00Z",
  updated_at = "2026-03-02T12:00:00Z",
  metadata = { author = "..." },
  content = { "# Body", "", "Markdown" }, -- string or string[]
}
```

Optional spec callbacks:

- `note_path(resource, ctx)`: relative note path inside the remote workspace for a new resource. Existing notes are never moved merely because this result changes.
- `render(resource, current_body, ctx)`: returns the complete new body. The default uses `resource.content`, preserves the current body when content is absent, and otherwise emits a title/link stub.
- `frontmatter(resource, ctx)`: additional provider-specific fields.

The workspace `path` must be absolute. `note_path` cannot escape that workspace. A new note cannot overwrite an unmanaged file. Adapter metadata cannot override the core ownership and lifecycle fields listed below.

## Frontmatter and ownership

Every managed note gets flat properties so they remain convenient in Obsidian Properties and Dataview:

```yaml
vault: yt-watch-later
resource_id: dQw4w9WgXcQ
url: https://www.youtube.com/watch?v=dQw4w9WgXcQ
title: Example
revision: opaque-v2
added_at: 2026-03-01T10:00:00Z
updated_at: 2026-03-02T12:00:00Z
imported_at: 2026-03-03T09:00:00Z
synced_at: 2026-03-03T09:00:00Z
status: active
```

`imported_at` is local and immutable. `added_at` and `updated_at` come from the provider. `synced_at` records the latest materialization. `resource_id` is used instead of `id` because Obsidian reserves `id` as the note ID. The current Obsidian frontmatter function must retain `note.metadata` (the built-in default does); otherwise ownership fields cannot be persisted.

The ownership pair is `(vault, resource_id)`. Files without that pair are never updated, archived, or deleted. Duplicate ownership is a hard error before writes.

The body returned by `render` is provider-owned. To preserve annotations, either keep them in separate notes or implement a `render` callback that retains a clearly delimited local section from `current_body`.

## Sync lifecycle

1. **Acquire per-remote lock** — overlapping runs of the same remote are rejected.
2. **List** — retrieve and validate the complete remote ID set. A list error causes zero local changes.
3. **Index** — scan the remote workspace for owned notes; archived notes are excluded.
4. **Plan** — classify IDs as create, update, unchanged, or remove.
5. **Hydrate and write** — fetch only creates/updates, then update body and frontmatter.
6. **Remove** — only runs if every fetch/write succeeded. This prevents a partial import from triggering destructive cleanup.
7. **Report** — release the lock and emit completion or error events.

A modified buffer is never overwritten. Archive/delete also refuse any loaded buffer because moving or removing it would leave a stale editor buffer.

Removal behavior:

- `archive`: mark the note `status: removed`, add `removed_at`, and move it under the remote workspace's `_archive/` directory while preserving its relative path.
- `delete`: remove the owned note.
- `keep`: leave it active and report it as kept; a later sync will consider it missing again.

## Events

The module emits these `User` autocommands:

- `ObsidianRemoteVaultSyncStart` with `{ name }`
- `ObsidianRemoteVaultSyncComplete` with `{ name, created, updated, unchanged, archived, deleted, kept, errors }`
- `ObsidianRemoteVaultSyncError` with `{ name, error }`

The full report is available to the `remote.sync()` callback; autocmd data is deliberately limited to serializable summary values.

## Adapter behavior

### GitHub

The built-in GitHub adapter:

- uses `OWNER/REPO#NUMBER` as its stable resource ID;
- uses `updatedAt` as its revision;
- stores repository, issue number/state, author, labels, and assignees as frontmatter;
- writes the issue body and comments into the note body;
- supports `state`, `assignee`, `author`, `labels`, `search`, `limit`, and additional `gh issue list` arguments.

### feed.nvim

The built-in feed adapter:

- treats the configured feed.nvim query as the complete collection;
- uses feed.nvim's database ID as its stable resource ID;
- includes title, source URL, author, feed name, and feed tags;
- writes the content already stored by feed.nvim without performing a second network fetch;
- accepts `transform(content, entry)` for HTML-to-Markdown or other conversion.

For example, with an HTML-to-Markdown converter:

```lua
remote.adapters.feed {
  path = vim.fn.expand "~/remote-vaults/rss",
  query = "+unread",
  transform = function(html)
    return my_html_to_markdown(html)
  end,
}
```

YouTube and Spotify remain custom-adapter candidates. The YouTube example above demonstrates the same contract needed by either.

## Deliberate v1 limits

- Pull-only; remote state is never mutated.
- Sequential hydration; correctness and API rate limits matter more than throughput initially.
- No automatic scheduling. Use a user command/autocmd/timer outside this module.
- No generic body merge. Providers opt into merge behavior through `render`.
- A sync always targets the workspace bound to that remote vault; it never depends on the active/default workspace.
