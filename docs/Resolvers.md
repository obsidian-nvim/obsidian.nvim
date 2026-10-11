# Resolvers

Resolvers are user-provided functions that choose or acquire input before an action continues.

They are different from `opts.callbacks`:

- `callbacks` observe lifecycle events after/during plugin work, and some have autocmd mirrors.
- `resolvers` are not hooks and do not emit autocmds. They receive context, then call `done()` with normalized data for the running action.

```lua
require("obsidian").setup {
  resolvers = {
    attachment = function(ctx, done)
      done { path = "/tmp/image.png" }
    end,

    date = function(ctx, done)
      done { timestamp = os.time(), precision = "day" }
    end,

    hints = function(ctx, done)
      done {}
    end,
  },
}
```

A resolver may be synchronous or asynchronous. Call `done(nil)` to cancel, or `done(nil, "message")` to fail with an error message.

## Attachment resolver

`opts.resolvers.attachment` is used by `require("obsidian.actions").add_attachment()` before the selected source is copied/downloaded and optionally inserted.

```lua
---@class obsidian.resolver.AttachmentCtx
---@field bufnr integer
---@field insert boolean|?
---@field source string|?
---@field cwd string
---@field vault_dir string
---@field intent string

---@class obsidian.resolver.AttachmentResult
---@field path string Local filepath, file URI, or URL accepted by `obsidian.attachment.add()`.
```

Example using an external picker:

```lua
require("obsidian").setup {
  resolvers = {
    attachment = function(ctx, done)
      require("my_picker").pick_file(function(path)
        if not path then
          done(nil)
          return
        end
        done { path = path }
      end)
    end,
  },
}
```

The built-in resolver keeps the default behavior: explicit file paths are used, directories open a file picker, missing sources prompt for a URL or filepath, and `http(s)` URLs are passed to the attachment API.

## Date resolver

`opts.resolvers.date` is used by daily-note picking APIs, including `:Obsidian dailies` through `daily.pick()`.

```lua
---@class obsidian.resolver.DateCtx
---@field intent string
---@field cadence string|?
---@field offset_start integer|?
---@field offset_end integer|?
---@field default_timestamp integer|?

---@class obsidian.resolver.DateResult
---@field timestamp integer Unix timestamp.
---@field precision string|?
---@field label string|?
---@field offset integer|?
```

Example using a calendar plugin:

```lua
require("obsidian").setup {
  resolvers = {
    date = function(ctx, done)
      require("calendar").pick_day(function(timestamp)
        done { timestamp = timestamp, precision = "day" }
      end)
    end,
  },
}
```

The built-in resolver keeps the default `:Obsidian dailies` picker UI.

## Hints resolver

`opts.resolvers.hints` builds the inlay hints for a note. Replacing it overrides the built-in link-suggestion hints.

```lua
---@class obsidian.resolver.HintsCtx
---@field bufnr integer
---@field note obsidian.Note
---@field range lsp.Range|?

---@alias obsidian.resolver.HintsResult lsp.InlayHint[]
```

The returned hints must be valid, serializable LSP inlay hints. Function-valued commands are not supported. To make a hint actionable, add the action to `lua/obsidian/actions.lua` and return a normal LSP command whose name is prefixed with `obsidian.`:

```lua
resolvers = {
  hints = function(ctx, done)
    done { {
      position = { line = 0, character = 4 },
      label = { {
        value = " ▶",
        command = {
          title = "Run hint action",
          command = "obsidian.my_hint_action",
          arguments = { "argument" },
        },
      } },
    } }
  end,
}
```

The built-in resolver returns link-suggestion hints for the requested range.

## Note preview resolver

`opts.resolvers.note_preview` renders the preview/documentation lines shown for a note, currently as documentation of LSP completion items (wiki links, headings, blocks, and "create new note" entries). Later features like hover or picker previews can reuse it with a different `ctx.scope`.

```lua
---@class obsidian.resolver.NotePreviewCtx
---@field scope string e.g. "lsp.completion"
---@field note obsidian.Note
---@field label string|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?

---@alias obsidian.resolver.NotePreviewResult string Markdown documentation.
```

The built-in resolver shows the note's path, id, aliases, tags, and a `**title:**` line resolved from the frontmatter `title` (if set), the first H1, or the first non-empty non-comment body line. It also shows the resolved link and the linked anchor/block when present.

Example adding the creation date from frontmatter:

```lua
require("obsidian").setup {
  resolvers = {
    note_preview = function(ctx, done)
      local created = ctx.note.metadata and ctx.note.metadata.created
      local base = require("obsidian.resolvers").default_note_preview(ctx)
      if created then
        done(base .. "\n**created:** " .. tostring(created))
      else
        done(base)
      end
    end,
  },
}
```

When a custom resolver cancels or fails, completion items fall back to the built-in rendering.
