---
title: "Resolvers"
tags:
  - developers
  - configuration
---

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

    date_select = function(ctx, done)
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

## Date selection and parsing

`opts.resolvers.date_select` chooses a date in `:Obsidian dailies` through `daily.pick()`. The previous `resolvers.date` name remains a deprecated alias for selection until 4.0. If both are set, `date_select` wins. The built-in selection resolver shows the daily-notes picker.

`opts.resolvers.date_parse` resolves the complete typed expression in `:Obsidian daily <expression>`. Bare `:Obsidian daily` opens today without calling it. The built-in parser accepts integer calendar-day offsets, `today`, `tomorrow`, `yesterday` (respecting `workdays_only`), and the formats accepted by `obsidian.date.parse`. Picker offsets do **not** use `date_parse`.

```lua
---@class obsidian.resolver.DateSelectCtx
---@field intent string
---@field cadence string|?
---@field offset_start integer|?
---@field offset_end integer|?
---@field default_timestamp integer|?

---@class obsidian.resolver.DateParseCtx
---@field input string Entire date expression, trimmed
---@field intent "open_daily"
---@field fallback obsidian.Resolver Built-in date_parse function

---@class obsidian.resolver.DateResult
---@field timestamp integer Unix timestamp.
---@field precision string|?
---@field label string|?
---@field offset integer|?
```

A custom parser receives **every** nonempty expression. Call `ctx.fallback(ctx, done)` to run the original built-in resolver; it uses the same callback and error handling as a custom resolver. This `ctx.fallback` contract is currently provided for `date_parse` only. As with other resolvers, `done(nil)` cancels rather than falling back.

```lua
require("obsidian").setup {
  resolvers = {
    date_parse = function(ctx, done)
      if ctx.input == "next review" then
        done { timestamp = os.time { year = 2026, month = 6, day = 25 }, precision = "day" }
      else
        ctx.fallback(ctx, done)
      end
    end,
    date_select = function(ctx, done)
      require("calendar").pick_day(function(timestamp)
        done { timestamp = timestamp, precision = "day" }
      end)
    end,
  },
}
```

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

The built-in resolver returns link-suggestion hints for the requested range. In insert mode, hints update with document changes except while the cursor is in a built-in completion expression (`[[`, `#`, or `[^`). During completion, the previous hint result is reused and no resolver is started; hints resume when completion ends or the cursor leaves the expression. A debounced refresh also follows normal-mode edits (including undo), leaving insert mode, and saving the note. Accepting a hint triggers a refresh.
