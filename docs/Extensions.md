---
title: "Extensions"
tags:
  - developers
  - extensions
---

**This is for developers**

Example integration: [obsidian-markmap.nvim](https://github.com/obsidian-nvim/obsidian-markmap.nvim).

## Add a command

Register subcommands through `require("obsidian").commands`, using the same `add`/`del` pattern as [[LSP#Code Action API|code actions]]. Pass your handler in the spec; you can keep its implementation anywhere in your plugin.

```lua
local commands = require("obsidian").commands

commands.add {
  name = "map",
  fn = function(data)
    require("my_plugin").map(data)
  end,
  cond = function(ctx)
    return ctx.in_note
  end,
}
```

Users can run `:Obsidian map` or select `map` from `:Obsidian`. The command also appears in subcommand completion when its condition holds.

### Command spec

| Field      | Type                                                      | Default   | Meaning                                                                                               |
| ---------- | --------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------- |
| `name`     | `string`                                                  | Required  | Unique subcommand name, using letters, digits, underscores, or hyphens.                               |
| `fn`       | `function(data)`                                          | Required  | Handler receiving Neovim user-command arguments, with the subcommand removed from `args` and `fargs`. |
| `cond`     | `function(ctx): boolean`                                  | Available | Availability check for the menu, completion, and execution.                                           |
| `nargs`    | nonnegative integer, `"0"`, `"1"`, `"?"`, `"+"`, or `"*"` | `0`       | Number of arguments accepted after the subcommand.                                                    |
| `range`    | `boolean`                                                 | `false`   | Whether the command accepts an explicit Ex range.                                                     |
| `complete` | function or string                                        | None      | Neovim completion function `(arg_lead, cmdline, cursor_pos)` or completion type such as `"file"`.     |

Registering an existing name replaces its spec. Invalid specs raise an error during registration.

### Conditional availability

`cond(ctx)` receives:

- `ctx.bufnr`: originating buffer number.
- `ctx.in_note`: `vim.b[ctx.bufnr].obsidian_buffer == true`, including supported note filetypes such as Quarto.
- `ctx.has_range`: whether the user supplied an Ex range, including a Visual selection range.

Read current config inside your condition so that workspace/config changes take effect without re-registering:

```lua
commands.add {
  name = "selection_map",
  range = true,
  fn = function(data)
    require("my_plugin").map_lines(data.line1, data.line2)
  end,
  cond = function(ctx)
    return ctx.in_note and ctx.has_range and Obsidian.opts.templates.enabled == true
  end,
}
```

`range = true` permits both ranged and non-ranged calls. Add `ctx.has_range` to the condition for a selection-only command. Use the range context rather than checking live Visual mode, since Neovim may have entered command-line mode by the time it checks availability.

Keep conditions free of side effects and return a boolean. A false condition hides the command and blocks explicit execution. If a condition throws or returns another type, obsidian.nvim treats the command as unavailable and warns once per distinct command/error.

The command menu preserves the originating buffer and range, then rechecks availability when the user selects an item. If the buffer no longer exists, obsidian.nvim rejects execution.

### Remove or override a command

```lua
commands.del "map"
commands.del "today" -- Built-ins use the same registry.
```

Deleting an unknown name does nothing. A deleted command stays absent for the session unless you add it again. You can override a built-in with `commands.add` using its name.

Register customizations after loading obsidian.nvim, for example in its `callbacks.post_setup` callback.

## Migrate from filename-based registration

`require("obsidian").register_command(name, config)` and `commands.register(name, config)` are deprecated. They still support `func`, `note_action`, and lazy lookup of `obsidian.commands.<name>`, but warn once per session.

Replace:

```lua
-- Required lua/obsidian/commands/map.lua to return the handler.
require("obsidian").register_command("map", { nargs = 0, note_action = true })
```

with:

```lua
require("obsidian").commands.add {
  name = "map",
  fn = function(data)
    require("my_plugin").map(data)
  end,
  cond = function(ctx)
    return ctx.in_note
  end,
}
```

Rename `func` to `fn` if you already supply a handler. Replace `note_action = true` with a condition checking `ctx.in_note`. The new API does not infer handler paths or require files under `lua/obsidian/commands/`.

This registration deprecation is separate from the legacy `:ObsidianToday`-style commands controlled by `legacy_commands`.
