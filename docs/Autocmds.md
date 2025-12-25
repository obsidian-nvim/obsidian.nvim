## Conventions

Autocmd events provide by this plugin follows following conventions:

- Corresponds to Vim autocmd if reasonable, like `BufWritePost` in a vault will trigger `ObsidianNoteWritePost`.

## Events

| name                    | triggered by                       | data               |
| ----------------------- | ---------------------------------- | ------------------ |
| `ObsidianNoteEnter`     | `BufEnter`                         |                    |
| `ObsidianNoteLeave`     | `BufLeave`                         |                    |
| `ObsidianNoteWritePost` | `BufWritePost`                     |                    |
| `ObsidianNoteWritePre`  | `BufWritePre`                      |                    |
| `ObsidianWorkspaceSet`  | When you enter or switch workspace | `workspace` object |

## How to use

```lua
vim.api.create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function(ev)
    local note = require("obsidian.note").from_buffer(ev.buf)
    --- anything you want to do
  end,
})
```

## Example

### Format code blocks

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteWritePost",
  callback = function(ev)
    require("conform").format {
      bufnr = ev.buf,
      formatters = { "prettier", "injected" },
    }
  end,
})
```

### Turn off spell based on frontmatter

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function(ev)
    local note = require("obsidian.note").from_buffer(ev.buf)
    if note and note.metadata and note.metadata.spell == false then
      vim.wo.spell = false
    end
  end,
})
```
