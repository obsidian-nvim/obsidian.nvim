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
