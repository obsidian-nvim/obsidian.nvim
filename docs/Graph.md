# Graph

Open the vault graph with `:Obsidian graph`. Use `:Obsidian graph %` for the current note's local graph, or pass a note path or vault folder. Enable `cache.enabled` to use the graph.

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
