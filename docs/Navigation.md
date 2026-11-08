---
title: "Navigation"
tags:
  - navigation
  - links
---

## Following links

Use `:Obsidian follow_link` or `require("obsidian.actions").follow_link()` to follow the link under the cursor. The action also accepts a link string:

```lua
require("obsidian.actions").follow_link("[Inbox](obsidian://open?file=Inbox)")
```

These use the same link handling as obsidian.nvim's LSP go-to-definition support. See [[Link]] for wiki/Markdown link formats and [[LSP]] for navigation setup.

## Obsidian URI links

Markdown links and autolinks with the `obsidian://` scheme run inside Neovim by default. You do not need the Obsidian app or an operating-system URI association:

```markdown
[Project](obsidian://open?vault=Notes&file=Projects%2FRoadmap)
[Next steps](obsidian://open?file=Projects%2FRoadmap%23Next%20steps)
[Block](obsidian://open?file=Projects%2FRoadmap%23%5Eblock-id)
<obsidian://daily>
```

Encode parameter values: spaces as `%20`, `/` as `%2F`, `#` as `%23`, and `&` as `%26`. Values remain encoded until the URI parser handles them, so content such as `a%26b` does not become another query parameter.

### Supported actions

| Action | Behavior |
| --- | --- |
| `open` | Switch workspace or open an existing note, with optional heading/block navigation. |
| `new` | Create a note or modify an existing note using `content`, `append`, `prepend`, or `overwrite`. |
| `daily` | Create or open today's note using the configured daily-note folder and template. Accepts the content options from `new`. |
| `unique` | Create and open a note using the configured unique-note folder, format, and template. |
| `search` | Open the note grep picker, optionally with `query`. Obsidian search operators are not translated. |
| `choose-vault` | Open the configured workspace picker. |

For `open` and `new`, `file` is relative to the vault root. For `new`, `file` overrides `name`; `name` uses the configured new-note location. An absolute `path` overrides `vault` and `file` and selects the most specific configured workspace containing it. Targets cannot escape the selected workspace through `..` or symlinks. Vault names and configured workspace names work; Obsidian vault IDs do not.

`paneType=tab` opens a Neovim tab and `paneType=split` uses a horizontal split. `paneType=window` has no Neovim equivalent and falls back to `open_notes_in` with a warning.

### Adding content

```markdown
[Capture](obsidian://new?file=Inbox&append&content=Remember%20this)
[Add task](obsidian://new?file=Inbox&heading=Tasks&spacing=newline&content=-%20Buy%20milk)
[Daily entry](obsidian://daily?append&heading=Log&content=Finished%20the%20review)
```

`heading` targets the first matching heading, ignoring case and optional leading `#` characters. Append includes child sections; prepend inserts below the heading and its existing leading blank lines. A missing heading returns an error without changing existing content. Put the heading in your daily-note template when targeting a new daily note.

A heading-targeted write defaults to append when neither `append` nor `prepend` is present. Otherwise, an existing note remains unchanged unless a mutation flag is present. `append` takes precedence over `prepend` and `overwrite`.

Use `spacing=auto` (the default) to separate inserted content with a blank line, `spacing=newline` for a new line, or `spacing=inline` for no added separator. `spacing` requires append/prepend or a heading that implies append. Use `silent` with `new` or `daily` to write without opening the note. `clipboard` reads Neovim's `+` register, falling back to `content` when the register is empty.

A new `new` note with explicit content does not gain a template or managed frontmatter. Append/prepend preserve existing frontmatter; properties in incoming content are not merged into it.

### Confirmation and scope

```lua
require("obsidian").setup {
  uri = {
    enabled = true,
    require_confirmation = true,
  },
}
```

Following `new`, `daily`, `unique`, or a file-modifying `open` URI prompts for confirmation before dispatch. Declining leaves the note and workspace unchanged. Keep confirmation enabled for links from untrusted notes.

Set `uri.enabled = false` to use the existing external-link opening policy instead. Other URI schemes keep that policy regardless of this setting. Direct Lua calls to the URI handler do not prompt.

Internal link navigation does not require a system URI association. For browser and Web Clipper entrypoints, see [[Obsidian-URI-Registration]]. See [[Obsidian-URI]] for the full action and callback reference.
